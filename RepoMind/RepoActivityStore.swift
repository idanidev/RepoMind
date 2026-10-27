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

    private let defaults: UserDefaults
    private let maxAge: TimeInterval

    private static let defaultsKey = "repoActivityCache"

    typealias Target = (account: GitHubAccount, repos: [(owner: String, name: String)], ids: [Int])

    /// Repos the last answer did not include: deleted, renamed or out of the token's reach. They are
    /// not asked for again on every appearance of the home, only when the user pulls or the hour ends.
    private var unresolved: Set<Int> = []

    init(defaults: UserDefaults = .standard, maxAge: TimeInterval = 60 * 60) {
        self.defaults = defaults
        self.maxAge = maxAge
        load()
    }

    /// Explicit and `nonisolated` on purpose. With the module's default isolation on the main
    /// actor, a synthesized `deinit` is main-actor isolated too, and Swift routes it through
    /// `swift_task_deinitOnExecutor`; the iOS 26 simulator runtime aborts in there ("pointer
    /// being freed was not allocated") when the object dies outside a task, which is exactly
    /// what killed the test host at the end of `RepoActivityStoreTests` (swiftlang/swift#85663).
    /// Nothing here needs the actor to be released.
    nonisolated deinit {}

    func activity(for repoID: Int) -> RepoActivity? {
        activities[repoID]
    }

    /// Forgets everything, on sign-out: the next account must not inherit this one's pull requests
    /// and builds, nor wait an hour for the first refresh.
    func reset() {
        activities = [:]
        lastRefresh = nil
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    var isStale: Bool {
        guard let lastRefresh else { return true }
        return Date.now.timeIntervalSince(lastRefresh) > maxAge
    }

    /// Whether a non-forced refresh has something to do: the hour is up, or a repo has no facts yet and
    /// GitHub has not said it cannot resolve it. Repos arrive from iCloud in batches, and the ones that
    /// come after a refresh must not wait an hour for their first numbers.
    func needsRefresh(for repos: [ProjectRepo]) -> Bool {
        if isStale { return true }
        return repos.contains { !$0.isLocal && activities[$0.repoID] == nil && !unresolved.contains($0.repoID) }
    }

    /// Returns when no refresh is running, or after `timeout`. A forced refresh asked for while another
    /// one is in the air returns at once, so whoever needs fresh numbers waits for the running one first.
    func waitUntilIdle(timeout: Duration = .seconds(15)) async {
        let deadline = ContinuousClock.now + timeout
        while isRefreshing, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// Refreshes every GitHub repo of every account, in one request per account.
    ///
    /// Skips silently when nothing needs it, when a refresh is already running, or when there is
    /// nothing to ask about yet (repos still arriving from CloudKit). The refresh is only stamped as
    /// done when GitHub actually answered for at least one account: a failed request, an expired token,
    /// a locked Keychain or a task cancelled halfway (the home restarts its `.task` every time CloudKit
    /// adds repos) used to be recorded as a success, which muted the next hour and put "refreshed just
    /// now" on a screen that had nothing new. A failure keeps what was cached, account by account — the
    /// repo sync is where token problems get reported to the user. What GitHub no longer resolves for
    /// an account that did answer is dropped, so a deleted repo does not keep a red build forever.
    func refresh(repos: [ProjectRepo], accounts: [GitHubAccount], force: Bool = false) async {
        guard !isRefreshing, force || needsRefresh(for: repos) else { return }
        let targets = Self.targets(repos: repos, accounts: accounts)
        guard !targets.isEmpty else { return }
        // Plain values: the models can go away while the requests are in the air (a sign-out, CloudKit).
        let jobs = targets.map { (tokenKey: $0.account.tokenKey, repos: $0.repos, ids: $0.ids) }

        isRefreshing = true
        defer { isRefreshing = false }

        var merged = activities
        var answered = false
        for job in jobs {
            guard let token = try? await KeychainManager.shared.retrieveToken(for: job.tokenKey),
                  !token.hasPrefix("mock")
            else { continue }
            let fetched = try? await GitHubService.shared.fetchRepoActivity(for: job.repos, token: token)
            if Task.isCancelled { return }
            guard let fetched else { continue }

            answered = true
            let returned = Set(fetched.map(\.repoID))
            for id in job.ids where !returned.contains(id) {
                merged[id] = nil
            }
            unresolved.subtract(returned)
            unresolved.formUnion(job.ids.filter { !returned.contains($0) })
            for activity in fetched {
                merged[activity.repoID] = activity
            }
        }
        guard answered else { return }
        activities = merged
        lastRefresh = .now
        save()
    }

    /// Local projects have no GitHub side; repos whose URL never parsed have no owner to ask for.
    static func targets(repos: [ProjectRepo], accounts: [GitHubAccount]) -> [Target] {
        accounts.compactMap { account -> Target? in
            let mine = repos
                .filter { !$0.isLocal && $0.account?.id == account.id }
                .compactMap { repo -> (id: Int, owner: String, name: String)? in
                    let parts = repo.fullName.split(separator: "/", maxSplits: 1)
                    guard parts.count == 2 else { return nil }
                    return (id: repo.repoID, owner: String(parts[0]), name: String(parts[1]))
                }
            guard !mine.isEmpty else { return nil }
            return (
                account: account,
                repos: mine.map { (owner: $0.owner, name: $0.name) },
                ids: mine.map(\.id)
            )
        }
    }

    // MARK: Persistence

    private func load() {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let snapshot = try? JSONDecoder().decode(RepoActivitySnapshot.self, from: data)
        else { return }
        activities = snapshot.activities
        lastRefresh = snapshot.lastRefresh
    }

    private func save() {
        let snapshot = RepoActivitySnapshot(lastRefresh: lastRefresh, activities: activities)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

// MARK: - Snapshot

/// What goes to `UserDefaults`: the cache and when it was last refreshed.
nonisolated private struct RepoActivitySnapshot: Codable {
    var lastRefresh: Date?
    var activities: [Int: RepoActivity]
}
