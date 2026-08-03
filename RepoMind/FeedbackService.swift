import Foundation
import SwiftData

// MARK: - GitHub API DTO

private struct GHIssueLabel: Decodable {
    let name: String
}

private struct GHIssue: Decodable {
    let number: Int
    let title: String
    let body: String?
    let html_url: String
    let state: String
    let created_at: String
    let updated_at: String
    let labels: [GHIssueLabel]
    let pull_request: PRMarker?

    struct PRMarker: Decodable {}
}

// MARK: - Service

@MainActor
final class FeedbackService {
    static let shared = FeedbackService()

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Shared session with sane timeouts for the GitHub API.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private init() {}

    /// Last poll timestamp per repo (`owner/repo` → ISO date string).
    private static let lastCheckKey = "FeedbackService.lastCheckByRepo"

    private func lastCheckMap() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: Self.lastCheckKey) as? [String: String] ?? [:]
    }

    private func setLastCheck(for repoFullName: String, date: Date) {
        var map = lastCheckMap()
        map[repoFullName] = isoFormatter.string(from: date)
        UserDefaults.standard.set(map, forKey: Self.lastCheckKey)
    }

    func lastCheck(for repoFullName: String) -> Date? {
        guard let str = lastCheckMap()[repoFullName] else { return nil }
        return isoFormatter.date(from: str)
    }

    /// Fetches issues with `user-feedback` label since last check, upserts in SwiftData.
    /// Returns the newly-created `FeedbackIssue` instances (not pre-existing ones) for notification dispatch.
    @discardableResult
    func sync(repo: ProjectRepo, token: String, into context: ModelContext) async throws -> [FeedbackIssue] {
        guard !repo.isLocal, !repo.htmlURL.isEmpty,
              let owner = parseOwner(from: repo.htmlURL),
              !owner.isEmpty
        else { return [] }
        let fullName = "\(owner)/\(repo.name)"

        var components = URLComponents(string: "https://api.github.com/repos/\(owner)/\(repo.name)/issues")!
        var items: [URLQueryItem] = [
            .init(name: "labels", value: "user-feedback"),
            .init(name: "state", value: "all"),
            .init(name: "per_page", value: "100"),
            .init(name: "sort", value: "updated"),
            .init(name: "direction", value: "desc")
        ]
        if let last = lastCheck(for: fullName) {
            items.append(.init(name: "since", value: isoFormatter.string(from: last)))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GitHubError.invalidResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let decoded = try JSONDecoder().decode([GHIssue].self, from: data)
        // Filter out pull requests (GitHub returns them as issues).
        let issues = decoded.filter { $0.pull_request == nil }

        // Batch fetch existing issues for this repo to avoid N+1 SwiftData queries.
        let existingDescriptor = FetchDescriptor<FeedbackIssue>(
            predicate: #Predicate { $0.repoFullName == fullName }
        )
        let existing = (try? context.fetch(existingDescriptor)) ?? []
        let existingByNumber = Dictionary(
            existing.map { ($0.issueNumber, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var newOnes: [FeedbackIssue] = []
        for gh in issues {
            let labels = gh.labels.map(\.name)
            let severity = FeedbackSeverity.from(labels: labels)
            let (source, rating) = parseSourceAndRating(body: gh.body ?? "")
            let createdAt = isoFormatter.date(from: gh.created_at) ?? .now
            let updatedAt = isoFormatter.date(from: gh.updated_at) ?? .now

            if let existing = existingByNumber[gh.number] {
                existing.title = gh.title
                existing.bodyText = gh.body ?? ""
                existing.htmlURL = gh.html_url
                existing.severityRaw = severity.rawValue
                existing.state = gh.state
                existing.source = source
                existing.rating = rating
                existing.updatedAt = updatedAt
            } else {
                let issue = FeedbackIssue(
                    issueNumber: gh.number,
                    repoFullName: fullName,
                    title: gh.title,
                    bodyText: gh.body ?? "",
                    htmlURL: gh.html_url,
                    severity: severity,
                    state: gh.state,
                    source: source,
                    rating: rating,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    isRead: false
                )
                context.insert(issue)
                newOnes.append(issue)
            }
        }
        try? context.save()
        setLastCheck(for: fullName, date: .now)
        return newOnes
    }

    /// Sync all non-local repos for a given account.
    /// Runs serially because `ModelContext` is not thread-safe — but checks Task.isCancelled between repos.
    @discardableResult
    func syncAll(repos: [ProjectRepo], token: String, into context: ModelContext) async -> [FeedbackIssue] {
        var collected: [FeedbackIssue] = []
        for repo in repos {
            if Task.isCancelled { break }
            do {
                collected.append(contentsOf: try await sync(repo: repo, token: token, into: context))
            } catch {
                // One repo failing shouldn't stop the rest, but swallowing it silently is how a
                // broken poll goes unnoticed for weeks.
                #if DEBUG
                    print("[Feedback] \(repo.name) failed to sync: \(error)")
                #endif
            }
        }
        return collected
    }

    // MARK: - Issue Mutations

    enum FeedbackError: LocalizedError {
        case noOwner
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .noOwner:
                return String(localized: "feedback_error_no_owner")
            case .http(let code, _):
                return String(format: String(localized: "feedback_error_http %lld"), code)
            }
        }
    }

    /// PATCH issue state=closed.
    func closeIssue(_ issue: FeedbackIssue, token: String, in context: ModelContext) async throws {
        try await patchIssue(issue, body: ["state": "closed"], token: token)
        issue.state = "closed"
        try? context.save()
    }

    /// PATCH issue state=open.
    func reopenIssue(_ issue: FeedbackIssue, token: String, in context: ModelContext) async throws {
        try await patchIssue(issue, body: ["state": "open"], token: token)
        issue.state = "open"
        try? context.save()
    }

    /// POST comment to an issue.
    func addComment(to issue: FeedbackIssue, body: String, token: String) async throws {
        let parts = issue.repoFullName.split(separator: "/")
        guard parts.count == 2 else { throw FeedbackError.noOwner }
        let url = URL(string: "https://api.github.com/repos/\(parts[0])/\(parts[1])/issues/\(issue.issueNumber)/comments")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["body": body])
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FeedbackError.http((resp as? HTTPURLResponse)?.statusCode ?? 0, String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// PUT replace labels (keeps `user-feedback` + new severity).
    func updateSeverity(_ issue: FeedbackIssue, to severity: FeedbackSeverity, token: String, in context: ModelContext) async throws {
        let parts = issue.repoFullName.split(separator: "/")
        guard parts.count == 2 else { throw FeedbackError.noOwner }
        var labels = ["user-feedback"]
        switch severity {
        case .critical: labels.append("bug:critical")
        case .minor: labels.append("bug:minor")
        case .enhancement: labels.append("enhancement")
        case .general: break
        }
        let url = URL(string: "https://api.github.com/repos/\(parts[0])/\(parts[1])/issues/\(issue.issueNumber)/labels")!
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["labels": labels])
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FeedbackError.http((resp as? HTTPURLResponse)?.statusCode ?? 0, String(data: data, encoding: .utf8) ?? "")
        }
        issue.severityRaw = severity.rawValue
        try? context.save()
    }

    private func patchIssue(_ issue: FeedbackIssue, body: [String: Any], token: String) async throws {
        let parts = issue.repoFullName.split(separator: "/")
        guard parts.count == 2 else { throw FeedbackError.noOwner }
        let url = URL(string: "https://api.github.com/repos/\(parts[0])/\(parts[1])/issues/\(issue.issueNumber)")!
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FeedbackError.http((resp as? HTTPURLResponse)?.statusCode ?? 0, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Helpers

    private func parseOwner(from htmlURL: String) -> String? {
        // e.g. https://github.com/owner/repo
        guard let url = URL(string: htmlURL) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        return parts.first
    }

    /// Body convention: optional `Source: email` / `Source: app_store_review` and `Rating: 4` lines.
    private func parseSourceAndRating(body: String) -> (source: String, rating: Int?) {
        var source = "github"
        var rating: Int?
        for raw in body.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if let val = line.dropPrefix("source:") {
                source = val.trimmingCharacters(in: .whitespaces)
            } else if let val = line.dropPrefix("rating:") {
                let digits = val.trimmingCharacters(in: .whitespaces).prefix(1)
                rating = Int(digits)
            }
        }
        return (source, rating)
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
