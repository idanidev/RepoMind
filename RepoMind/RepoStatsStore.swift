import Foundation
import Observation

// MARK: - Repo stats store

/// Where each repo's statistics endpoint lives, and what it last said.
///
/// Per repo: the endpoint URL in `UserDefaults`, the token in the Keychain, and the last
/// `RepoStats` on disk so the page opens with numbers before the network answers. Deliberately
/// not SwiftData: the endpoint is a device setting and the data is a cache, and neither should
/// travel through CloudKit or force a schema deploy. Refreshed at most once an hour unless the
/// user pulls.
@MainActor
@Observable
final class RepoStatsStore {
    static let shared = RepoStatsStore()

    private(set) var stats: [Int: RepoStats] = [:]
    private(set) var fetchedAt: [Int: Date] = [:]
    private(set) var loading: Set<Int> = []
    /// The last failure per repo, in the user's language. Cleared by the next success.
    private(set) var failures: [Int: String] = [:]

    private let defaults: UserDefaults
    private let maxAge: TimeInterval
    private let session: URLSession

    init(defaults: UserDefaults = .standard, maxAge: TimeInterval = 60 * 60, session: URLSession = .shared) {
        self.defaults = defaults
        self.maxAge = maxAge
        self.session = session
    }

    /// Explicit and `nonisolated` for the same reason as in `RepoActivityStore`: a synthesized
    /// main-actor `deinit` crashes the iOS 26 simulator runtime when the object dies outside a task.
    nonisolated deinit {}

    // MARK: Configuration

    func endpoint(for repoID: Int) -> URL? {
        defaults.string(forKey: Self.endpointKey(repoID)).flatMap(URL.init(string:))
    }

    func isConfigured(_ repoID: Int) -> Bool {
        endpoint(for: repoID) != nil
    }

    /// Stores the endpoint and the token, and forgets the throttle so the next refresh runs.
    func configure(repoID: Int, endpoint: URL, token: String) async throws {
        try await KeychainManager.shared.saveToken(token, for: Self.tokenKey(repoID))
        defaults.set(endpoint.absoluteString, forKey: Self.endpointKey(repoID))
        failures[repoID] = nil
        fetchedAt[repoID] = nil
    }

    func disconnect(repoID: Int) async {
        try? await KeychainManager.shared.deleteToken(for: Self.tokenKey(repoID))
        defaults.removeObject(forKey: Self.endpointKey(repoID))
        defaults.removeObject(forKey: Self.cacheKey(repoID))
        stats[repoID] = nil
        fetchedAt[repoID] = nil
        failures[repoID] = nil
    }

    /// Forgets every connected app (endpoint, token and cache), on sign-out.
    func disconnectAll() async {
        let prefix = "repoStatsEndpoint_"
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            if let repoID = Int(key.dropFirst(prefix.count)) {
                await disconnect(repoID: repoID)
            }
        }
        stats = [:]
        fetchedAt = [:]
        failures = [:]
    }

    // MARK: Reading

    /// What memory holds. Pure, so a view can call it while rendering.
    func stats(for repoID: Int) -> RepoStats? {
        stats[repoID]
    }

    func isStale(_ repoID: Int) -> Bool {
        guard let date = fetchedAt[repoID] else { return true }
        return Date.now.timeIntervalSince(date) > maxAge
    }

    /// Brings the disk cache of these repos into memory, for the ones memory has nothing on.
    func loadCached(for repoIDs: [Int]) {
        for repoID in repoIDs where stats[repoID] == nil {
            guard let snapshot = loadSnapshot(repoID) else { continue }
            stats[repoID] = snapshot.stats
            fetchedAt[repoID] = snapshot.fetchedAt
        }
    }

    /// Asks the endpoint again when the cache is older than an hour, or always when forced. A
    /// failure keeps the last numbers and records why, so the page can say so.
    func refresh(repoID: Int, force: Bool = false) async {
        loadCached(for: [repoID])
        guard let endpoint = endpoint(for: repoID) else { return }
        guard force || isStale(repoID), !loading.contains(repoID) else { return }
        loading.insert(repoID)
        defer { loading.remove(repoID) }

        guard let token = try? await KeychainManager.shared.retrieveToken(for: Self.tokenKey(repoID)) else {
            failures[repoID] = String(localized: "stats_error_token")
            return
        }
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await session.data(for: request)
            // Disconnected while the request was in the air: an answer that lands now must not bring
            // the numbers, and their cache on disk, back.
            guard self.endpoint(for: repoID) != nil else { return }
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard http.statusCode == 200 else {
                failures[repoID] = String(format: String(localized: "stats_error_status %lld"), http.statusCode)
                return
            }
            let fresh = try RepoStats.decode(data)
            stats[repoID] = fresh
            fetchedAt[repoID] = .now
            failures[repoID] = nil
            saveSnapshot(repoID, fresh)
        } catch {
            // A refresh that was cancelled (the screen went away, the background time ran out) says
            // nothing about the endpoint, and was being shown to the user as its failure.
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            failures[repoID] = error.localizedDescription
        }
    }

    // MARK: Persistence

    private func loadSnapshot(_ repoID: Int) -> RepoStatsSnapshot? {
        guard let data = defaults.data(forKey: Self.cacheKey(repoID)) else { return nil }
        return try? JSONDecoder().decode(RepoStatsSnapshot.self, from: data)
    }

    private func saveSnapshot(_ repoID: Int, _ stats: RepoStats) {
        let snapshot = RepoStatsSnapshot(fetchedAt: .now, stats: stats)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.cacheKey(repoID))
    }

    private static func endpointKey(_ repoID: Int) -> String { "repoStatsEndpoint_\(repoID)" }
    private static func tokenKey(_ repoID: Int) -> String { "stats-\(repoID)" }
    private static func cacheKey(_ repoID: Int) -> String { "repoStatsCache_\(repoID)" }
}

// MARK: - Snapshot

/// What goes to `UserDefaults` per repo: the stats and when they were fetched.
nonisolated private struct RepoStatsSnapshot: Codable {
    var fetchedAt: Date
    var stats: RepoStats
}
