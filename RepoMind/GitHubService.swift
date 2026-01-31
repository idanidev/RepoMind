import Foundation
import SwiftData

// MARK: - GitHub API DTOs

struct GitHubUser: Decodable, Sendable {
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

struct GitHubRepo: Decodable, Sendable, Identifiable {
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
            String(localized: "El token de GitHub es inválido o ha expirado.")
        case .networkError(let error):
            String(localized: "Error de red: \(error.localizedDescription)")
        case .invalidResponse(let code):
            String(localized: "El servidor respondió con código \(code).")
        case .decodingError(let error):
            String(localized: "Error al procesar la respuesta: \(error.localizedDescription)")
        case .noToken:
            String(localized: "No se encontró token de GitHub. Inicia sesión.")
        }
    }
}

// MARK: - GitHub Service

actor GitHubService {
    static let shared = GitHubService()

    private let baseURL = "https://api.github.com"
    private let session: URLSession
    private let decoder: JSONDecoder

    // ✅ FIX: Retry configuration
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 1.0

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        ]
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
    }

    // MARK: - Validate Token

    func validateToken(_ token: String) async throws -> GitHubUser {
        if token == "mock-pro" {
            return GitHubUser(
                login: "ProDev", avatarUrl: "person.fill.checkmark", name: "Pro Developer",
                bio: "Mock Pro Account")
        }
        if token == "mock-free" {
            return GitHubUser(
                login: "FreeDev", avatarUrl: "person.fill", name: "Free Developer",
                bio: "Mock Free Account")
        }
        if token == "mock-pro-personal" {
            return GitHubUser(
                login: "ProPersonal", avatarUrl: "figure.gaming", name: "Pro Personal",
                bio: "Mock Side Projects")
        }

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
        if token == "mock-pro" { return generateMockRepos(count: 10) }
        if token == "mock-free" { return generateMockRepos(count: 4) }
        if token == "mock-pro-personal" {
            return generateMockRepos(count: 5, prefix: "Side Project")
        }

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
        if token == "mock-pro" || token == "mock-free" { return [101, 103] }

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

        for remote in remoteRepos {
            let remoteID = remote.id
            var fetchDescriptor = FetchDescriptor<ProjectRepo>(
                predicate: #Predicate { $0.repoID == remoteID })
            fetchDescriptor.fetchLimit = 1

            let existing = try context.fetch(fetchDescriptor)
            let parsedDate =
                formatter.date(from: remote.updatedAt) ?? fallbackFormatter.date(
                    from: remote.updatedAt) ?? .now
            let isStarred = starredIDs.contains(remote.id)

            if let repo = existing.first {
                repo.name = remote.name
                repo.repoDescription = remote.description ?? ""
                repo.updatedAt = parsedDate
                repo.htmlURL = remote.htmlUrl
                repo.language = remote.language
                repo.stargazersCount = remote.stargazersCount
                repo.account = account
                if isStarred { repo.isFavorite = true }
            } else {
                let repo = ProjectRepo(
                    repoID: remote.id,
                    name: remote.name,
                    repoDescription: remote.description ?? "",
                    updatedAt: parsedDate,
                    htmlURL: remote.htmlUrl,
                    isFavorite: isStarred,
                    language: remote.language,
                    stargazersCount: remote.stargazersCount,
                    account: account
                )
                context.insert(repo)
            }
        }

        try context.save()
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
}
