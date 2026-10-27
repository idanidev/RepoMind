import XCTest

@testable import RepoMind

/// What signing out must leave behind nothing of: the caches and checkpoints the stores keep in
/// `UserDefaults`. (The Keychain half needs a device; `SessionReset` calls it last.)
@MainActor
final class SessionResetTests: XCTestCase {
    private let suiteName = "SessionResetTests"

    private func suite() throws -> UserDefaults {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    func testTheAlertsMemoryIsForgottenSoTheNextAccountStartsQuiet() throws {
        let defaults = try suite()
        let seen = [7: RepoAlertRules.Seen(checksState: "SUCCESS", releaseTag: "v1")]
        defaults.set(try JSONEncoder().encode(seen), forKey: "repoAlertsSeen")

        let center = RepoAlertCenter(defaults: defaults)
        center.reset()

        XCTAssertNil(defaults.data(forKey: "repoAlertsSeen"))
    }

    func testTheActivityCacheIsForgottenAndTheNextRefreshIsDueAtOnce() {
        // The standard defaults with the key cleared, like the other tests of this store.
        let defaults = UserDefaults.standard
        defaults.set(Data("stale".utf8), forKey: "repoActivityCache")

        let store = RepoActivityStore(defaults: defaults)
        store.reset()

        XCTAssertNil(defaults.data(forKey: "repoActivityCache"))
        XCTAssertNil(store.lastRefresh)
        XCTAssertTrue(store.isStale)
    }

    func testEveryTaskLabelGoesAndNothingElseDoes() throws {
        let defaults = try suite()
        let first = UUID()
        let second = UUID()
        TaskLabelStore.set(TaskLabels(kind: .bug, delegated: true), for: first, defaults: defaults)
        TaskLabelStore.set(TaskLabels(kind: .idea, delegated: false), for: second, defaults: defaults)
        defaults.set("kept", forKey: "voiceCustomVocabulary")

        TaskLabelStore.removeAll(defaults: defaults)

        XCTAssertNil(TaskLabelStore.labels(for: first, defaults: defaults))
        XCTAssertNil(TaskLabelStore.labels(for: second, defaults: defaults))
        XCTAssertEqual(defaults.string(forKey: "voiceCustomVocabulary"), "kept")
    }

    func testStoreStatusAndConnectedAppsAreDisconnected() async throws {
        let defaults = try suite()
        let store = RepoStatsStore(defaults: defaults)
        defaults.set("https://example.com/stats", forKey: "repoStatsEndpoint_42")
        defaults.set(Data("cache".utf8), forKey: "repoStatsCache_42")
        defaults.set("https://example.com/other", forKey: "repoStatsEndpoint_43")

        await store.disconnectAll()

        XCTAssertFalse(store.isConfigured(42))
        XCTAssertFalse(store.isConfigured(43))
        XCTAssertNil(defaults.data(forKey: "repoStatsCache_42"))
    }
}
