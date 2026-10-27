import XCTest

@testable import RepoMind

@MainActor
final class StoreStatusStoreTests: XCTestCase {
    private let suiteName = "StoreStatusStoreTests"
    private var defaults: UserDefaults = .standard

    private let json = """
        { "schema": 1, "generatedAt": "2026-10-27T06:31:00Z",
          "apps": [ { "id": "1", "name": "RepoMind", "bundleId": "idanidev.RepoMind",
                      "versions": [ { "platform": "IOS", "version": "1.5.2", "state": "READY_FOR_SALE" } ],
                      "builds": [] } ] }
        """
    private let address = "https://raw.githubusercontent.com/idanidev/RepoMind/store-data/store.json"

    /// Counts the downloads without a captured `var`, which a `@Sendable` closure may not mutate.
    private nonisolated final class Calls: @unchecked Sendable {
        var count = 0
        var lastToken: String?
    }

    override func setUp() {
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore(calls: Calls = Calls(), data: Data? = nil) -> StoreStatusStore {
        let payload = data ?? Data(json.utf8)
        return StoreStatusStore(defaults: defaults, maxAge: 3600) { _, token in
            calls.count += 1
            calls.lastToken = token
            return payload
        }
    }

    // MARK: Pure helpers

    func testOnlyAnHttpsAddressIsAccepted() {
        XCTAssertNotNil(StoreStatusStore.validated(address))
        XCTAssertNotNil(StoreStatusStore.validated("  \(address)\n"))
        XCTAssertNil(StoreStatusStore.validated("http://raw.githubusercontent.com/a/b/c/store.json"))
        XCTAssertNil(StoreStatusStore.validated("store.json"))
        XCTAssertNil(StoreStatusStore.validated("https://localhost/store.json"))
        XCTAssertNil(StoreStatusStore.validated(""))
    }

    func testTheGitHubTokenOnlyGoesToGitHub() throws {
        XCTAssertTrue(StoreStatusStore.sendsToken(to: try XCTUnwrap(URL(string: address))))
        XCTAssertFalse(StoreStatusStore.sendsToken(to: try XCTUnwrap(URL(string: "https://example.com/store.json"))))
        let lookalike = try XCTUnwrap(URL(string: "https://evil.example/raw.githubusercontent.com"))
        XCTAssertFalse(StoreStatusStore.sendsToken(to: lookalike))
    }

    func testTheAccountIsTheOneThatOwnsTheRepoElseTheFirst() throws {
        let mine = StoreAccount(username: "idanidev", tokenKey: "a")
        let other = StoreAccount(username: "someone", tokenKey: "b")
        let url = try XCTUnwrap(URL(string: address))
        XCTAssertEqual(StoreStatusStore.account(for: url, in: [other, mine]), mine)
        XCTAssertEqual(StoreStatusStore.account(for: url, in: [other]), other)
        XCTAssertNil(StoreStatusStore.account(for: url, in: []))
    }

    // MARK: Configuration

    func testConfiguringKeepsTheAddressAndDisconnectingForgetsEverything() async {
        let store = makeStore()
        XCTAssertFalse(store.isConfigured)
        XCTAssertFalse(store.configure("not a url"))
        XCTAssertFalse(store.isConfigured)

        XCTAssertTrue(store.configure(address))
        XCTAssertTrue(store.isConfigured)
        await store.refresh(accounts: [])
        XCTAssertNotNil(store.status)

        store.disconnect()
        XCTAssertFalse(store.isConfigured)
        XCTAssertNil(store.status)
        XCTAssertNil(store.fetchedAt)
        XCTAssertNil(defaults.data(forKey: "storeStatusCache"))
    }

    // MARK: Refreshing

    func testRefreshReadsTheFileAndKeepsItOnDisk() async throws {
        let calls = Calls()
        let store = makeStore(calls: calls)
        store.configure(address)
        await store.refresh(accounts: [])
        XCTAssertEqual(store.status?.apps.first?.name, "RepoMind")
        XCTAssertNotNil(store.fetchedAt)
        XCTAssertNil(store.failure)
        XCTAssertEqual(calls.count, 1)

        // A new store over the same defaults opens with the cache, before any network.
        let later = makeStore()
        XCTAssertNil(later.status)
        later.loadCached()
        XCTAssertEqual(later.status?.apps.first?.name, "RepoMind")
        XCTAssertNotNil(later.fetchedAt)
    }

    func testRefreshIsThrottledUnlessForced() async {
        let calls = Calls()
        let store = makeStore(calls: calls)
        store.configure(address)
        await store.refresh(accounts: [])
        await store.refresh(accounts: [])
        XCTAssertEqual(calls.count, 1)
        await store.refresh(accounts: [], force: true)
        XCTAssertEqual(calls.count, 2)
    }

    func testAnAddressThatIsNotConfiguredReadsNothing() async {
        let calls = Calls()
        let store = makeStore(calls: calls)
        await store.refresh(accounts: [], force: true)
        XCTAssertEqual(calls.count, 0)
        XCTAssertNil(store.status)
    }

    func testAFailureIsReportedAndKeepsWhatWasThere() async {
        let good = makeStore()
        good.configure(address)
        await good.refresh(accounts: [])
        XCTAssertNotNil(good.status)

        let failing = StoreStatusStore(defaults: defaults, maxAge: 3600) { _, _ in
            throw GitHubError.invalidResponse(404)
        }
        failing.loadCached()
        await failing.refresh(accounts: [], force: true)
        XCTAssertNotNil(failing.failure)
        XCTAssertNotNil(failing.status, "the last good answer stays on screen")
    }

    func testAFileInAnotherFormatIsAFailureNotACrash() async {
        let store = makeStore(data: Data("{\"schema\": 9}".utf8))
        store.configure(address)
        await store.refresh(accounts: [])
        XCTAssertNotNil(store.failure)
        XCTAssertNil(store.status)
    }
}
