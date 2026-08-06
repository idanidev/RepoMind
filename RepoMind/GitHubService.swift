import Foundation
import SwiftData

// MARK: - GitHub API DTOs

nonisolated struct GitHubUser: Decodable, Sendable {
    let login: String
    let avatarUrl: String
    let name: String?
    let bio: String?

    enum CodingKeys: String, CodingKey {
        case login
        case avatarUrl = "avatar_url"
        case name
        case bio
    }
}

nonisolated struct RepoContentItem: Decodable, Sendable, Identifiable {
    let name: String
    let path: String
    let type: String   // "file" or "dir"
    let downloadUrl: String?

    var id: String { path }

    var isImage: Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(".png") || lower.hasSuffix(".jpg") ||
               lower.hasSuffix(".jpeg") || lower.hasSuffix(".gif") ||
               lower.hasSuffix(".webp")
    }

    enum CodingKeys: String, CodingKey {
        case name, path, type
        case downloadUrl = "download_url"
    }
}

nonisolated struct GitHubRepo: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String
    let description: String?
    let updatedAt: String
    let htmlUrl: String
    let isPrivate: Bool
    let language: String?
    let stargazersCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case updatedAt = "updated_at"
        case htmlUrl = "html_url"
        case isPrivate = "private"
        case language
        case stargazersCount = "stargazers_count"
    }
}

// MARK: - GitHub Service Errors

enum GitHubError: LocalizedError {
    case invalidToken
    case networkError(Error)
    case invalidResponse(Int)
    case decodingError(Error)
    case noToken

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            String(localized: "github_token_invalid")
        case .networkError(let error):
            String(format: String(localized: "github_network_error"), error.localizedDescription)
        case .invalidResponse(let code):
            String(format: String(localized: "github_invalid_response"), code)
        case .decodingError(let error):
            String(format: String(localized: "github_decoding_error"), error.localizedDescription)
        case .noToken:
            String(localized: "github_no_token")
        }
    }
}

// MARK: - GitHub Service

actor GitHubService {
    static let shared = GitHubService()

    private let baseURL = "https://api.github.com"
    private let session: URLSession
    private let decoder: JSONDecoder

    private let maxRetries = 2
    private let retryDelay: TimeInterval = 0.5

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        ]
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    // MARK: - Validate Token

    func validateToken(_ token: String) async throws -> GitHubUser {
        #if DEBUG
        if token == "mock-pro" {
            return GitHubUser(
                login: "ProDev", avatarUrl: "", name: "Pro Developer",
                bio: "Mock Pro Account")
        }
        if token == "mock-free" {
            return GitHubUser(
                login: "FreeDev", avatarUrl: "", name: "Free Developer",
                bio: "Mock Free Account")
        }
        if token == "mock-pro-personal" {
            return GitHubUser(
                login: "ProPersonal", avatarUrl: "figure.gaming", name: "Pro Personal",
                bio: "Mock Side Projects")
        }
        #endif

        let request = try buildRequest(path: "/user", token: token)
        let (data, response) = try await performRequestWithRetry(request)

        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse(0)
        }

        switch http.statusCode {
        case 200:
            return try decoder.decode(GitHubUser.self, from: data)
        case 401:
            throw GitHubError.invalidToken
        default:
            throw GitHubError.invalidResponse(http.statusCode)
        }
    }

    // MARK: - Fetch Repos

    func fetchRepos(token: String, page: Int = 1, perPage: Int = 50) async throws -> [GitHubRepo] {
        #if DEBUG
        if token == "mock-pro" { return generateMockRepos(count: 10) }
        if token == "mock-free" { return generateMockRepos(count: 4) }
        if token == "mock-pro-personal" {
            return generateMockRepos(count: 5, prefix: "Side Project")
        }
        #endif

        let request = try buildRequest(
            path: "/user/repos?sort=updated&per_page=\(perPage)&page=\(page)&type=all",
            token: token
        )
        let (data, response) = try await performRequestWithRetry(request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if (response as? HTTPURLResponse)?.statusCode == 401 { throw GitHubError.invalidToken }
            throw GitHubError.invalidResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        return try decoder.decode([GitHubRepo].self, from: data)
    }

    // MARK: - Fetch Repo Contents (File Browser)

    func fetchContents(owner: String, repo: String, path: String, token: String) async throws -> [RepoContentItem] {
        let encodedPath = path.isEmpty ? "" : "/\(path)"
        let request = try buildRequest(
            path: "/repos/\(owner)/\(repo)/contents\(encodedPath)",
            token: token
        )
        let (data, response) = try await performRequestWithRetry(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitHubError.invalidResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try decoder.decode([RepoContentItem].self, from: data)
    }

    // ✅ NEW: Fetch all repos with automatic pagination
    func fetchAllRepos(token: String, maxPages: Int = 5) async throws -> [GitHubRepo] {
        var allRepos: [GitHubRepo] = []
        var page = 1

        while page <= maxPages {
            let repos = try await fetchRepos(token: token, page: page, perPage: 100)
            if repos.isEmpty { break }
            allRepos.append(contentsOf: repos)
            if repos.count < 100 { break }
            page += 1
        }

        return allRepos
    }

    // MARK: - Fetch Starred

    func fetchStarredRepoIDs(token: String) async throws -> Set<Int> {
        #if DEBUG
        if token == "mock-pro" || token == "mock-free" { return [101, 103] }
        #endif

        var starredIDs: Set<Int> = []
        var page = 1

        while page <= 3 {
            let request = try buildRequest(
                path: "/user/starred?per_page=50&page=\(page)", token: token)

            guard let (data, response) = try? await performRequestWithRetry(request),
                let http = response as? HTTPURLResponse,
                http.statusCode == 200
            else { break }

            let repos = try decoder.decode([GitHubRepo].self, from: data)
            if repos.isEmpty { break }

            for repo in repos { starredIDs.insert(repo.id) }
            page += 1
        }

        return starredIDs
    }

    // MARK: - Sync Repos

    /// Syncs ALL remote repos into the local database (no limit at data layer).
    /// Free-tier visibility limits are enforced at the UI layer to guarantee
    /// consistent data regardless of API ordering or re-syncs.
    @MainActor
    func syncRepos(account: GitHubAccount, token: String, into context: ModelContext) async throws {
        async let remoteReposTask = fetchAllRepos(token: token)
        async let starredIDsTask = fetchStarredRepoIDs(token: token)

        let remoteRepos = try await remoteReposTask
        let starredIDs = (try? await starredIDsTask) ?? []

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        // Single fetch — avoids N+1 queries (one per remote repo)
        let allLocal = try context.fetch(FetchDescriptor<ProjectRepo>())
        // Scoped to the account being synced. Grouping every repo by `repoID` alone treated the
        // same repository connected under two GitHub accounts as a duplicate: one copy was deleted
        // and the survivor reassigned to whichever account synced last.
        // Orphans (account == nil, left over from older builds) are included so they get adopted
        // here rather than duplicated.
        let ownedLocal = allLocal.filter { $0.account?.id == account.id || $0.account == nil }
        let localByID = Dictionary(grouping: ownedLocal, by: \.repoID)

        // Track whether anything actually changed to avoid unnecessary CloudKit writes
        var madeChanges = false
        var newReposForLogoFetch: [(ProjectRepo, String, String, String?)] = []

        for remote in remoteRepos {
            let existing = localByID[remote.id] ?? []
            let parsedDate =
                formatter.date(from: remote.updatedAt) ?? fallbackFormatter.date(
                    from: remote.updatedAt) ?? .now
            let isStarred = starredIDs.contains(remote.id)

            // Deduplicación: CloudKit puede crear duplicados temporales al mergear
            if existing.count > 1 {
                for duplicate in existing.dropFirst() {
                    context.delete(duplicate)
                }
                madeChanges = true
            }

            if let repo = existing.first {
                // Only update — and only mark dirty — when something actually changed.
                // Using updatedAt as the primary change signal; also check account link
                // and star status independently since they can change without a repo update.
                let dateChanged = abs(repo.updatedAt.timeIntervalSince(parsedDate)) > 1
                let accountChanged = repo.account?.id != account.id
                let starChanged = isStarred && !repo.isFavorite

                if dateChanged {
                    repo.name = remote.name
                    repo.repoDescription = remote.description ?? ""
                    repo.updatedAt = parsedDate
                    repo.htmlURL = remote.htmlUrl
                    repo.language = remote.language
                    repo.stargazersCount = remote.stargazersCount
                    madeChanges = true
                }
                if accountChanged {
                    repo.account = account
                    madeChanges = true
                }
                if starChanged {
                    repo.isFavorite = true
                    madeChanges = true
                }
                // No buscamos logo aquí para repos existentes (ya lo tienen o el usuario lo configuró)
            } else {
                // Crear repo nuevo
                let repo = ProjectRepo(
                    repoID: remote.id,
                    name: remote.name,
                    repoDescription: remote.description ?? "",
                    updatedAt: parsedDate,
                    htmlURL: remote.htmlUrl,
                    isFavorite: isStarred,
                    language: remote.language,
                    stargazersCount: remote.stargazersCount,
                    logoURL: nil,
                    account: account
                )
                context.insert(repo)
                madeChanges = true

                // Collect new repos for batched logo fetching below
                let ownerName: String
                if let url = URL(string: remote.htmlUrl), url.pathComponents.count >= 2 {
                    ownerName = url.pathComponents[1]
                } else {
                    ownerName = account.username
                }
                newReposForLogoFetch.append((repo, ownerName, remote.name, remote.language))
            }
        }

        // Only write to CloudKit when something actually changed
        if madeChanges {
            try context.save()
        }

        // Fetch logos with limited concurrency (max 5 simultaneous) to avoid GitHub rate limits
        if !newReposForLogoFetch.isEmpty {
            let repoData = newReposForLogoFetch
            Task.detached {
                await withTaskGroup(of: (Int, String?).self) { group in
                    var running = 0
                    for (index, item) in repoData.enumerated() {
                        if running >= 5 {
                            if let result = await group.next() {
                                if let logoURL = result.1 {
                                    let idx = result.0
                                    await MainActor.run { repoData[idx].0.logoURL = logoURL }
                                }
                            }
                            running -= 1
                        }
                        group.addTask {
                            let url = await self.fetchRepoLogoURL(
                                owner: item.1, repo: item.2, token: token, language: item.3)
                            return (index, url)
                        }
                        running += 1
                    }
                    for await result in group {
                        if let logoURL = result.1 {
                            let idx = result.0
                            await MainActor.run { repoData[idx].0.logoURL = logoURL }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Fetch Repo Logo

    /// Estrategia por capas:
    /// 1. App Store Search API (solo Swift/ObjC)
    /// 2. AppIcon.appiconset en el repo (solo Swift/ObjC)
    /// 3. Avatar del owner como fallback universal
    func fetchRepoLogoURL(owner: String, repo: String, token: String, language: String? = nil) async -> String? {
        let isAppleRepo = language == "Swift" || language == "Objective-C"

        // Tier 1: App Store Search (apps publicadas)
        if isAppleRepo {
            if let appStoreURL = await searchAppStoreIcon(repoName: repo) {
                return appStoreURL
            }
        }

        // Tier 2: AppIcon en el repositorio
        if isAppleRepo {
            if let repoIcon = await findAppIconInRepo(owner: owner, repo: repo, token: token) {
                return repoIcon
            }
        }

        // Tier 3: Avatar del owner/org (siempre disponible, sin llamadas extra)
        return "https://avatars.githubusercontent.com/\(owner)"
    }

    /// Busca el icono en el App Store usando la iTunes Search API
    private func searchAppStoreIcon(repoName: String) async -> String? {
        let searchTerm = repoName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        guard let encoded = searchTerm.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=software&limit=5") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }

            struct AppStoreResponse: Decodable {
                let results: [AppStoreApp]
            }
            struct AppStoreApp: Decodable {
                let trackName: String
                let artworkUrl512: String?
            }

            let result = try decoder.decode(AppStoreResponse.self, from: data)

            // Normalizar nombre del repo para comparar
            let normalizedRepo = repoName.lowercased()
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: "_", with: "")

            for app in result.results {
                let normalizedApp = app.trackName.lowercased()
                    .replacingOccurrences(of: " ", with: "")
                // Match exacto o el repo contiene el nombre de la app (o viceversa)
                if normalizedApp == normalizedRepo ||
                   normalizedApp.contains(normalizedRepo) ||
                   normalizedRepo.contains(normalizedApp) {
                    return app.artworkUrl512
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    /// Busca AppIcon.appiconset dentro del repositorio
    private func findAppIconInRepo(owner: String, repo: String, token: String) async -> String? {
        // Rutas comunes donde suele estar el AppIcon
        let assetsPaths = [
            "\(repo)/Assets.xcassets/AppIcon.appiconset",
            "Assets.xcassets/AppIcon.appiconset",
            "App/Assets.xcassets/AppIcon.appiconset",
            "Sources/Assets.xcassets/AppIcon.appiconset",
            "iOS/Assets.xcassets/AppIcon.appiconset",
            "\(repo)/\(repo)/Assets.xcassets/AppIcon.appiconset",
        ]

        for assetsPath in assetsPaths {
            if let logoURL = await findPNGInPath(owner: owner, repo: repo, path: assetsPath, token: token) {
                return logoURL
            }
        }

        // Búsqueda recursiva
        if let logoURL = await searchForAppIconRecursively(owner: owner, repo: repo, token: token, path: "", depth: 0) {
            return logoURL
        }

        // Fallback: logos comunes en el repo
        let fallbackPaths = [
            "logo.png", "icon.png", "Logo.png", "Icon.png",
            "assets/logo.png", "assets/icon.png",
            "docs/logo.png", ".github/logo.png",
        ]

        for branch in ["main", "master"] {
            for path in fallbackPaths {
                let rawURL = "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(path)"
                if await checkURLExists(rawURL, token: token) {
                    return rawURL
                }
            }
        }

        return nil
    }

    /// Busca recursivamente en el repositorio hasta encontrar Assets.xcassets/AppIcon.appiconset
    private func searchForAppIconRecursively(
        owner: String, repo: String, token: String, path: String, depth: Int
    ) async -> String? {
        // Limitar profundidad para no hacer demasiadas llamadas
        guard depth < 3 else { return nil }

        let apiURL =
            path.isEmpty
            ? "https://api.github.com/repos/\(owner)/\(repo)/contents"
            : "https://api.github.com/repos/\(owner)/\(repo)/contents/\(path)"

        guard let url = URL(string: apiURL) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }

            struct GitHubItem: Decodable {
                let name: String
                let type: String
                let path: String
            }

            let items = try decoder.decode([GitHubItem].self, from: data)

            // Buscar Assets.xcassets
            for item in items where item.type == "dir" {
                if item.name == "Assets.xcassets" {
                    // Encontramos Assets.xcassets, buscar AppIcon.appiconset dentro
                    let appIconPath = "\(item.path)/AppIcon.appiconset"
                    if let logoURL = await findPNGInPath(
                        owner: owner, repo: repo, path: appIconPath, token: token)
                    {
                        return logoURL
                    }
                }

                // Carpetas donde podría estar Assets.xcassets (limitar búsqueda)
                let searchableFolders = ["Sources", "App", "iOS", repo, "src", "Source"]
                if searchableFolders.contains(item.name) {
                    if let logoURL = await searchForAppIconRecursively(
                        owner: owner, repo: repo, token: token, path: item.path, depth: depth + 1
                    ) {
                        return logoURL
                    }
                }
            }
        } catch {
            return nil
        }

        return nil
    }

    /// Busca el primer archivo .png en un directorio del repo
    private func findPNGInPath(owner: String, repo: String, path: String, token: String) async
        -> String?
    {
        let apiURL = "https://api.github.com/repos/\(owner)/\(repo)/contents/\(path)"

        guard let url = URL(string: apiURL) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }

            // Decodificar la lista de archivos
            struct GitHubFile: Decodable {
                let name: String
                let download_url: String?
            }

            let files = try decoder.decode([GitHubFile].self, from: data)

            // Buscar el primer PNG que sea un icono grande (preferir @3x o @2x)
            let pngFiles = files.filter { $0.name.hasSuffix(".png") }

            // Priorizar iconos grandes
            if let icon3x = pngFiles.first(where: {
                $0.name.contains("@3x") || $0.name.contains("180") || $0.name.contains("1024")
            }) {
                return icon3x.download_url
            }
            if let icon2x = pngFiles.first(where: {
                $0.name.contains("@2x") || $0.name.contains("120") || $0.name.contains("60")
            }) {
                return icon2x.download_url
            }
            // Cualquier PNG
            if let anyPng = pngFiles.first {
                return anyPng.download_url
            }
        } catch {
            return nil
        }

        return nil
    }

    /// Verifica si una URL existe
    private func checkURLExists(_ urlString: String, token: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                return http.statusCode == 200
            }
        } catch {
            return false
        }

        return false
    }

    // MARK: - Helpers

    private func buildRequest(path: String, token: String) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else {
            throw GitHubError.networkError(URLError(.badURL))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    // ✅ FIX: Add retry logic
    private func performRequestWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse)
    {
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                return try await session.data(for: request)
            } catch {
                lastError = error
                if let urlError = error as? URLError,
                    [.cancelled, .userAuthenticationRequired, .badURL].contains(urlError.code)
                {
                    throw GitHubError.networkError(error)
                }
                if attempt < maxRetries {
                    try? await Task.sleep(for: .seconds(retryDelay * pow(2.0, Double(attempt - 1))))
                }
            }
        }

        throw GitHubError.networkError(lastError ?? URLError(.unknown))
    }

    #if DEBUG
    private func generateMockRepos(count: Int, prefix: String = "Project Alpha") -> [GitHubRepo] {
        let languages = ["Swift", "Python", "JavaScript", "Go", "Rust"]
        let baseID = prefix == "Project Alpha" ? 100 : (prefix == "Side Project" ? 300 : 200)

        return (1...count).map { i in
            GitHubRepo(
                id: baseID + i,
                name: "\(prefix) \(i)",
                description: "Mock repository #\(i)",
                updatedAt: ISO8601DateFormatter().string(
                    from: Date().addingTimeInterval(Double(-i * 3600))),
                htmlUrl: "https://github.com/mock/project-\(i)",
                isPrivate: i % 3 == 0,
                language: languages[i % languages.count],
                stargazersCount: i * 42
            )
        }
    }
    #endif

    // MARK: - Star/Unstar Repos (Sync with GitHub)

    /// Star a repository on GitHub
    func starRepo(owner: String, repo: String, token: String) async throws {
        #if DEBUG
        guard !token.hasPrefix("mock-") else { return }
        #endif

        let urlString = "\(baseURL)/user/starred/\(owner)/\(repo)"
        guard let url = URL(string: urlString) else {
            throw GitHubError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("0", forHTTPHeaderField: "Content-Length")

        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse(0)
        }

        // 204 = starred successfully, 304 = already starred
        guard http.statusCode == 204 || http.statusCode == 304 else {
            throw GitHubError.invalidResponse(http.statusCode)
        }
    }

    /// Unstar a repository on GitHub
    func unstarRepo(owner: String, repo: String, token: String) async throws {
        #if DEBUG
        guard !token.hasPrefix("mock-") else { return }
        #endif

        let urlString = "\(baseURL)/user/starred/\(owner)/\(repo)"
        guard let url = URL(string: urlString) else {
            throw GitHubError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (_, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse(0)
        }

        // 204 = unstarred successfully, 304 = already not starred
        guard http.statusCode == 204 || http.statusCode == 304 || http.statusCode == 404 else {
            throw GitHubError.invalidResponse(http.statusCode)
        }
    }
}
