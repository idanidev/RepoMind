import Foundation

// MARK: - Repo activity

/// Facts about a repo that only GitHub knows, fetched in bulk by
/// `GitHubService.fetchRepoActivity` and kept by `RepoActivityStore`.
nonisolated struct RepoActivity: Codable, Hashable, Sendable {
    let repoID: Int
    var pushedAt: Date?
    var isPrivate = false
    var openPullRequests = 0
    var latestReleaseTag: String?
    /// GitHub's rollup of the default branch's last commit: `SUCCESS`, `FAILURE`, `ERROR`,
    /// `PENDING` or `EXPECTED`. `nil` when nothing runs checks on the repo.
    var checksState: String?
    /// Open Dependabot alerts. `nil` when the token cannot see them, which GitHub answers with
    /// a null field rather than an error for the whole repo.
    var securityAlerts: Int?
    var fetchedAt: Date

    var isBuildFailing: Bool { checksState == "FAILURE" || checksState == "ERROR" }
}

// MARK: - GraphQL document

/// One GraphQL document for a batch of repos, and the parser for its answer.
///
/// REST needs three or four calls per repo for the same facts, which across a whole list is
/// what the weekly sync cadence protects against. Here every repo is an aliased field of one
/// query, so a refresh costs a single request and one rate-limit point per batch.
nonisolated enum RepoActivityQuery {
    static let endpointPath = "/graphql"
    static let batchSize = 50

    /// Empty when no repo in the batch has a usable name.
    static func document(for repos: [(owner: String, name: String)]) -> String {
        let fields = repos.enumerated().compactMap { index, repo -> String? in
            guard isValidName(repo.owner), isValidName(repo.name) else { return nil }
            return "r\(index): repository(owner: \"\(repo.owner)\", name: \"\(repo.name)\") { ...activity }"
        }
        guard !fields.isEmpty else { return "" }
        return """
        query { \(fields.joined(separator: " ")) }
        fragment activity on Repository {
          databaseId
          pushedAt
          isPrivate
          pullRequests(states: OPEN) { totalCount }
          latestRelease { tagName }
          vulnerabilityAlerts(states: OPEN) { totalCount }
          defaultBranchRef { target { ... on Commit { statusCheckRollup { state } } } }
        }
        """
    }

    /// Repos GitHub could not resolve come back as `null` with an entry in `errors`; they are
    /// skipped, and the rest of the batch is still used.
    static func parse(_ data: Data, fetchedAt: Date = .now) throws -> [RepoActivity] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let formatter = ISO8601DateFormatter()
        return (response.data ?? [:]).values.compactMap { node -> RepoActivity? in
            guard let node, let repoID = node.databaseId else { return nil }
            return RepoActivity(
                repoID: repoID,
                pushedAt: node.pushedAt.flatMap { formatter.date(from: $0) },
                isPrivate: node.isPrivate ?? false,
                openPullRequests: node.pullRequests?.totalCount ?? 0,
                latestReleaseTag: node.latestRelease?.tagName,
                checksState: node.defaultBranchRef?.target?.statusCheckRollup?.state,
                securityAlerts: node.vulnerabilityAlerts?.totalCount,
                fetchedAt: fetchedAt
            )
        }
    }

    /// GitHub owners and repo names are letters, digits, `-`, `_` and `.`. Anything else cannot
    /// be a real repo, and dropping it keeps the document free of injected quotes.
    static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || "-_.".unicodeScalars.contains(scalar)
        }
    }

    // MARK: Wire format

    nonisolated private struct Response: Decodable {
        let data: [String: Node?]?
    }

    nonisolated private struct Node: Decodable {
        let databaseId: Int?
        let pushedAt: String?
        let isPrivate: Bool?
        let pullRequests: Count?
        let latestRelease: Release?
        let vulnerabilityAlerts: Count?
        let defaultBranchRef: BranchRef?
    }

    nonisolated private struct Count: Decodable {
        let totalCount: Int
    }

    nonisolated private struct Release: Decodable {
        let tagName: String?
    }

    nonisolated private struct BranchRef: Decodable {
        let target: Target?
    }

    nonisolated private struct Target: Decodable {
        let statusCheckRollup: Rollup?
    }

    nonisolated private struct Rollup: Decodable {
        let state: String?
    }
}
