import XCTest

@testable import RepoMind

final class StoreAlertTests: XCTestCase {
    private let all: Set<RepoAlertRules.Kind> = Set(RepoAlertRules.Kind.allCases)

    private func app(_ versions: [(String, String)]) -> StoreStatus.StoreApp {
        StoreStatus.StoreApp(
            id: "6740000000", name: "RepoMind", bundleId: "idanidev.RepoMind",
            versions: versions.map { StoreStatus.Version(platform: "IOS", version: $0.0, state: $0.1, createdAt: nil) })
    }

    private func seen(live: String, pending: String = "") -> RepoAlertRules.Seen {
        var seen = RepoAlertRules.Seen()
        seen.storeSignature = "\(live)|\(pending)"
        return seen
    }

    func testFirstSightIsRecordedNotAnnounced() {
        let result = RepoAlertRules.storeAlert(
            previous: nil, app: app([("1.5.2", "READY_FOR_SALE")]), name: "RepoMind", enabled: all)
        XCTAssertNil(result.alert)
        XCTAssertEqual(result.seen.storeSignature, "1.5.2|")
    }

    func testANewLiveVersionIsAnnouncedAndBeatsEverythingElse() throws {
        let result = RepoAlertRules.storeAlert(
            previous: seen(live: "1.5.2", pending: "1.5.3:IN_REVIEW"),
            app: app([("1.5.3", "READY_FOR_SALE"), ("1.5.2", "REPLACED_WITH_NEW_VERSION")]),
            name: "RepoMind", enabled: all)
        let alert = try XCTUnwrap(result.alert)
        XCTAssertEqual(alert.kind, .store)
        XCTAssertEqual(alert.repoID, 6_740_000_000)
        XCTAssertTrue(alert.title.contains("1.5.3"))
        XCTAssertTrue(alert.title.contains("RepoMind"))
        XCTAssertEqual(result.seen.storeSignature, "1.5.3|")
    }

    func testReviewApprovalAndRejectionEachAnnounce() throws {
        let previous = seen(live: "1.5.2", pending: "1.5.3:WAITING_FOR_REVIEW")
        for state in ["IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "REJECTED"] {
            let result = RepoAlertRules.storeAlert(
                previous: previous, app: app([("1.5.3", state), ("1.5.2", "READY_FOR_SALE")]),
                name: "RepoMind", enabled: all)
            let alert = try XCTUnwrap(result.alert, state)
            XCTAssertTrue(alert.title.contains("1.5.3"), state)
            XCTAssertEqual(result.seen.storeSignature, "1.5.2|1.5.3:\(state)")
        }
    }

    func testTheDevelopersOwnStepsStayQuiet() {
        // Submitting a version (waiting for review) or preparing one is not news to the developer.
        let submitted = RepoAlertRules.storeAlert(
            previous: seen(live: "1.5.2", pending: "1.5.3:PREPARE_FOR_SUBMISSION"),
            app: app([("1.5.3", "WAITING_FOR_REVIEW"), ("1.5.2", "READY_FOR_SALE")]),
            name: "RepoMind", enabled: all)
        XCTAssertNil(submitted.alert)
        XCTAssertEqual(submitted.seen.storeSignature, "1.5.2|1.5.3:WAITING_FOR_REVIEW")
    }

    func testNothingChangedAndADisabledKindStayQuietButKeepTheLatest() {
        let same = RepoAlertRules.storeAlert(
            previous: seen(live: "1.5.2", pending: "1.5.3:IN_REVIEW"),
            app: app([("1.5.3", "IN_REVIEW"), ("1.5.2", "READY_FOR_SALE")]), name: "RepoMind", enabled: all)
        XCTAssertNil(same.alert)

        let disabled = RepoAlertRules.storeAlert(
            previous: seen(live: "1.5.2"), app: app([("1.5.3", "READY_FOR_SALE")]), name: "RepoMind", enabled: [])
        XCTAssertNil(disabled.alert)
        XCTAssertEqual(disabled.seen.storeSignature, "1.5.3|", "turning it back on must not replay old news")
    }

    func testTheStoreAlertLeadsToTheAppInAppStoreConnect() throws {
        let alert = RepoAlertRules.Alert(kind: .store, repoID: 6_740_000_000, title: "t", body: "b")
        let url = try XCTUnwrap(URL(string: "https://appstoreconnect.apple.com/apps/6740000000/distribution"))
        XCTAssertEqual(RepoAlertRules.target(for: alert, htmlURL: ""), .web(url))
    }
}
