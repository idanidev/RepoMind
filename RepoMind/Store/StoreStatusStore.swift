import Foundation
import Observation

/// An account the store can read with: its GitHub username and where its token is kept.
nonisolated struct StoreAccount: Hashable, Sendable {
    let username: String
    let tokenKey: String
}

// MARK: - Store status store

/// Where the App Store status lives, and what it last said.
///
/// One URL for the whole developer account, kept in `UserDefaults`, pointing at the `store.json`
/// the scheduled workflow publishes (`docs/store-contract.md`). It is read with the GitHub token of
/// the account that owns the repo, so a private repo works, and the last answer stays on disk so
/// Home opens with numbers before the network replies. Deliberately not SwiftData, for the same reason
/// as `RepoActivityStore`: it is a device setting and a cache, and neither should travel through CloudKit.
@MainActor
@Observable
final class StoreStatusStore {
    static let shared = StoreStatusStore()
    static let urlKey = "storeStatusURL"

    private static let cacheKey = "storeStatusCache"
    private static let fetchedKey = "storeStatusFetchedAt"

    private(set) var status: StoreStatus?
    private(set) var fetchedAt: Date?
    private(set) var loading = false
    /// The last failure, in the user's language. Cleared by the next success.
    private(set) var failure: String?

    private let defaults: UserDefaults
    private let maxAge: TimeInterval
    private let download: @Sendable (URL, String?) async throws -> Data

    init(
        defaults: UserDefaults = .standard,
        maxAge: TimeInterval = 60 * 60,
        download: @escaping @Sendable (URL, String?) async throws -> Data = { url, token in
            try await GitHubService.shared.download(url, token: token)
        }
    ) {
        self.defaults = defaults
        self.maxAge = maxAge
        self.download = download
    }

    /// Explicit and `nonisolated` like the other stores: a synthesized main-actor `deinit` aborts the
    /// iOS 26 runtime when the object dies outside a task (swiftlang/swift#85663, see CLAUDE.md).
    nonisolated deinit {}

    // MARK: Configuration

    var endpoint: URL? {
        defaults.string(forKey: Self.urlKey).flatMap(URL.init(string:))
    }

    var isConfigured: Bool { endpoint != nil }

    /// An https URL, as the user pasted it. False when it is not one, and nothing changes.
    @discardableResult
    func configure(_ text: String) -> Bool {
        guard let url = Self.validated(text) else { return false }
        defaults.set(url.absoluteString, forKey: Self.urlKey)
        failure = nil
        fetchedAt = nil
        return true
    }

    func disconnect() {
        defaults.removeObject(forKey: Self.urlKey)
        defaults.removeObject(forKey: Self.cacheKey)
        defaults.removeObject(forKey: Self.fetchedKey)
        status = nil
        fetchedAt = nil
        failure = nil
    }

    // MARK: Reading

    var isStale: Bool {
        guard let fetchedAt else { return true }
        return Date.now.timeIntervalSince(fetchedAt) > maxAge
    }

    /// Brings the disk cache into memory, when memory has nothing.
    func loadCached() {
        guard status == nil, let data = defaults.data(forKey: Self.cacheKey),
            let cached = try? StoreStatus.decode(data)
        else { return }
        status = cached
        let stamp = defaults.double(forKey: Self.fetchedKey)
        fetchedAt = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    /// Reads the JSON again, at most once an hour unless `force`.
    func refresh(accounts: [StoreAccount], force: Bool = false) async {
        guard let url = endpoint, force || isStale, !loading else { return }
        loading = true
        defer { loading = false }

        var token: String?
        if Self.sendsToken(to: url), let account = Self.account(for: url, in: accounts) {
            token = try? await KeychainManager.shared.retrieveToken(for: account.tokenKey)
        }
        do {
            let data = try await download(url, token)
            // Disconnected while the request was in the air: do not bring the status back.
            guard endpoint != nil else { return }
            let decoded = try StoreStatus.decode(data)
            status = decoded
            fetchedAt = .now
            failure = nil
            defaults.set(data, forKey: Self.cacheKey)
            defaults.set(Date.now.timeIntervalSince1970, forKey: Self.fetchedKey)
        } catch {
            // Cancelled (the home restarts its task whenever CloudKit adds repos) is not a failure of
            // the file, and was being shown in red in Settings.
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            failure = Self.message(for: error)
        }
    }

    // MARK: Pure helpers

    /// https only: the file travels with a token in its header, and must not go in the clear.
    static func validated(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme == "https", let host = url.host, host.contains(".")
        else { return nil }
        return url
    }

    /// The GitHub token goes to GitHub and nowhere else, whatever URL was pasted.
    static func sendsToken(to url: URL) -> Bool {
        url.host == "raw.githubusercontent.com"
    }

    /// The account whose username owns the repo in a raw URL; with no match, the only account there is
    /// or the first one, which is what a developer with a single login means.
    static func account(for url: URL, in accounts: [StoreAccount]) -> StoreAccount? {
        let owner = url.pathComponents.dropFirst().first?.lowercased()
        return accounts.first { $0.username.lowercased() == owner } ?? accounts.first
    }

    static func message(for error: Error) -> String {
        if let github = error as? GitHubError {
            switch github {
            case .invalidToken: return String(localized: "store_error_token")
            case .invalidResponse(404): return String(localized: "store_error_not_found")
            default: break
            }
        }
        if error is DecodingError { return String(localized: "store_error_format") }
        return error.localizedDescription
    }
}
