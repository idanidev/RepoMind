import Foundation
import Observation

// MARK: - Repo activity store

/// What GitHub knows about each repo and the app does not store: open pull requests, latest
/// release, CI state, last push and visibility.
///
/// Deliberately not SwiftData. These facts are volatile and cheap to ask for again, and every
/// `@Model` field has to be deployed to the CloudKit schema before a release — a step that has
/// already broken sync once. A JSON blob in `UserDefaults` survives relaunches and offline use,
/// and goes stale after an hour, which is how often the home asks GitHub again. One GraphQL
/// request covers every repo of an account, so a refresh costs the rate limit a single point.
@MainActor
@Observable
final class RepoActivityStore {
    static let shared = RepoActivityStore()

    private(set) var activities: [Int: RepoActivity] = [:]
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let maxAge: TimeInterval

    private static let defaultsKey = "repoActivityCache"

    typealias Target = (account: GitHubAccount, repos: [(owner: String, name: String)])

    init(defaults: UserDefaults = .standard, maxAge: TimeInterval = 60 * 60) {
        self.defaults = defaults
        self.maxAge = maxAge
        load()
    }

    func activity(for repoID: Int) -> RepoActivity? {
        activities[repoID]
    }

    var isStale: Bool {
        guard let lastRefresh else { return true }
        return Date.now.timeIntervalSince(lastRefresh) > maxAge
    }

    /// Refreshes every GitHub repo of every account, in one request per account.
    ///
    /// Skips silently when nothing is stale, when a refresh is already running, or when there is
    /// nothing to ask about yet (repos still arriving from CloudKit): marking an empty run as a
    /// refresh would mute the next hour. A failed request keeps what was cached — the repo sync
    /// is where token problems get reported to the user.
    func refresh(repos: [ProjectRepo], accounts: [GitHubAccount], force: Bool = false) async {
        guard force || isStale, !isRefreshing else { return }
        let targets = Self.targets(repos: repos, accounts: accounts)
        guard !targets.isEmpty else { return }

        isRefreshing = true
        defer { isRefreshing = false }

        var merged = activities
        for target in targets {
            guard let token = try? await KeychainManager.shared.retrieveToken(for: target.account.tokenKey),
                  !token.hasPrefix("mock")
            else { continue }
            guard let fetched = try? await GitHubService.shared.fetchRepoActivity(
                for: target.repos, token: token)
            else { continue }
            for activity in fetched {
                merged[activity.repoID] = activity
            }
        }
        activities = merged
        lastRefresh = .now
        save()
    }

    /// Local projects have no GitHub side; repos whose URL never parsed have no owner to ask for.
    static func targets(repos: [ProjectRepo], accounts: [GitHubAccount]) -> [Target] {
        accounts.compactMap { account -> Target? in
            let mine = repos
                .filter { !$0.isLocal && $0.account?.id == account.id }
                .compactMap { repo -> (owner: String, name: String)? in
                    let parts = repo.fullName.split(separator: "/", maxSplits: 1)
                    guard parts.count == 2 else { return nil }
                    return (owner: String(parts[0]), name: String(parts[1]))
                }
            return mine.isEmpty ? nil : (account: account, repos: mine)
        }
    }

    // MARK: Persistence

    nonisolated private struct Snapshot: Codable {
        var lastRefresh: Date?
        var activities: [Int: RepoActivity]
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        activities = snapshot.activities
        lastRefresh = snapshot.lastRefresh
    }

    private func save() {
        let snapshot = Snapshot(lastRefresh: lastRefresh, activities: activities)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
