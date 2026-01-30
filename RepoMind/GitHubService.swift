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

nonisolated enum GitHubError: LocalizedError {
    case invalidToken
    case networkError(Error)
    case invalidResponse(Int)
    case decodingError(Error)
    case noToken

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            "El token de GitHub es invalido o ha expirado."
        case .networkError(let error):
            "Error de red: \(error.localizedDescription)"
        case .invalidResponse(let code):
            "El servidor respondio con codigo \(code)."
        case .decodingError(let error):
            "Error al procesar la respuesta: \(error.localizedDescription)"
        case .noToken:
            "No se encontro token de GitHub. Inicia sesion."
        }
    }
}

// MARK: - GitHub Service

actor GitHubService {
    static let shared = GitHubService()

    private let baseURL = "https://api.github.com"
    private let session: URLSession
    private nonisolated let decoder: JSONDecoder

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

    // MARK: - Validate Token (GET /user)

    func validateToken(_ token: String) async throws -> GitHubUser {
        // Mock Scenarios
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
        let (data, response) = try await performRequest(request)

        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse(0)
        }

        switch http.statusCode {
        case 200:
            do {
                return try decoder.decode(GitHubUser.self, from: data)
            } catch {
                throw GitHubError.decodingError(error)
            }
        case 401:
            throw GitHubError.invalidToken
        default:
            throw GitHubError.invalidResponse(http.statusCode)
        }
    }

    // MARK: - Fetch Repos

    func fetchRepos(token: String, page: Int = 1, perPage: Int = 50) async throws -> [GitHubRepo] {
        // Mock Scenarios
        if token == "mock-pro" {
            return generateMockRepos(count: 10)
        }
        if token == "mock-free" {
            return generateMockRepos(count: 4)
        }
        if token == "mock-pro-personal" {
            return generateMockRepos(count: 5, prefix: "Side Project")
        }

        let request = try buildRequest(
            path: "/user/repos?sort=updated&per_page=\(perPage)&page=\(page)&type=all",
            token: token
        )
        let (data, response) = try await performRequest(request)

        guard let http = response as? HTTPURLResponse else {
            throw GitHubError.invalidResponse(0)
        }

        guard http.statusCode == 200 else {
            if http.statusCode == 401 { throw GitHubError.invalidToken }
            throw GitHubError.invalidResponse(http.statusCode)
        }

        do {
            return try decoder.decode([GitHubRepo].self, from: data)
        } catch {
            throw GitHubError.decodingError(error)
        }
    }

    // MARK: - Fetch Starred Repo IDs

    func fetchStarredRepoIDs(token: String) async throws -> Set<Int> {
        // Mock Scenarios
        if token == "mock-pro" || token == "mock-free" {
            return [101, 103]  // Hardcoded favorites
        }

        var starredIDs: Set<Int> = []
        var page = 1

        // Fetch up to 3 pages (150 starred repos)
        while page <= 3 {
            let request = try buildRequest(
                path: "/user/starred?per_page=50&page=\(page)",
                token: token
            )
            let (data, response) = try await performRequest(request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                break
            }

            let repos = try decoder.decode([GitHubRepo].self, from: data)
            if repos.isEmpty { break }

            for repo in repos {
                starredIDs.insert(repo.id)
            }

            page += 1
        }

        return starredIDs
    }

    // MARK: - Sync Repos to SwiftData

    @MainActor
    func syncRepos(account: GitHubAccount, token: String, into context: ModelContext) async throws {

        // Fetch repos and starred IDs concurrently
        async let remoteReposTask = fetchRepos(token: token)
        async let starredIDsTask = fetchStarredRepoIDs(token: token)

        let remoteRepos: [GitHubRepo]
        let starredIDs: Set<Int>

        do {
            remoteRepos = try await remoteReposTask
        } catch {
            throw error
        }

        // Starred is best-effort — don't fail the whole sync if it errors
        starredIDs = (try? await starredIDsTask) ?? []

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        for remote in remoteRepos {
            let remoteID = remote.id
            let fetchDescriptor = FetchDescriptor<ProjectRepo>(
                predicate: #Predicate { $0.repoID == remoteID }
            )

            let existing = try context.fetch(fetchDescriptor)

            let parsedDate =
                formatter.date(from: remote.updatedAt)
                ?? fallbackFormatter.date(from: remote.updatedAt)
                ?? .now

            let isStarred = starredIDs.contains(remote.id)

            if let repo = existing.first {
                // Update existing
                repo.name = remote.name
                repo.repoDescription = remote.description ?? ""
                repo.updatedAt = parsedDate
                repo.htmlURL = remote.htmlUrl
                repo.language = remote.language
                repo.stargazersCount = remote.stargazersCount
                repo.account = account  // Link to account
                // Auto-mark as favorite if user starred it on GitHub (don't un-favorite manually set ones)
                if isStarred {
                    repo.isFavorite = true
                }
            } else {
                // Insert new
                let repo = ProjectRepo(
                    repoID: remote.id,
                    name: remote.name,
                    repoDescription: remote.description ?? "",
                    updatedAt: parsedDate,
                    htmlURL: remote.htmlUrl,
                    isFavorite: isStarred,
                    language: remote.language,
                    stargazersCount: remote.stargazersCount,
                    account: account  // Link to account
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

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw GitHubError.networkError(error)
        }
    }

    // MARK: - Mock Generator

    private func generateMockRepos(count: Int, prefix: String = "Project Alpha") -> [GitHubRepo] {
        var repos: [GitHubRepo] = []
        let languages = ["Swift", "Python", "JavaScript", "Go", "Rust"]

        // Stable IDs:
        // ProDev (count 10): 101...110
        // FreeDev (count 4): 201...204
        // ProPersonal (count 5): 301...305 (based on prefix)
        let baseID = prefix == "Project Alpha" ? 100 : (prefix == "Side Project" ? 300 : 200)

        for i in 1...count {
            let repo = GitHubRepo(
                id: baseID + i,  // Stable ID
                name: "\(prefix) \(i)",
                description: "This is a mock repository generated for testing loop #\(i)",
                updatedAt: ISO8601DateFormatter().string(
                    from: Date().addingTimeInterval(Double(-i * 3600))),
                htmlUrl: "https://github.com/mock/project-\(i)",
                isPrivate: i % 3 == 0,
                language: languages[i % languages.count],
                stargazersCount: i * 42
            )
            repos.append(repo)
        }
        return repos
    }
}
