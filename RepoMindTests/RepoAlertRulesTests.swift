import XCTest

@testable import RepoMind

final class RepoAlertRulesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_043_200)
    private let all: Set<RepoAlertRules.Kind> = Set(RepoAlertRules.Kind.allCases)

    private func facts(checks: String?, tag: String? = nil, security: Int? = nil) -> RepoActivity {
        RepoActivity(
            repoID: 1, pushedAt: now, isPrivate: false, openPullRequests: 0, latestReleaseTag: tag,
            checksState: checks, securityAlerts: security, fetchedAt: now)
    }

    func testFirstSightIsRecordedNotAnnounced() {
        let result = RepoAlertRules.gitHubAlerts(
            previous: nil, activity: facts(checks: "FAILURE", tag: "v1", security: 3), repoName: "InSync",
            enabled: all)
        XCTAssertTrue(result.alerts.isEmpty)
        XCTAssertEqual(result.seen.checksState, "FAILURE")
        XCTAssertEqual(result.seen.releaseTag, "v1")
        XCTAssertEqual(result.seen.securityAlerts, 3)
    }

    func testBuildGoingRedReleaseChangingAndMoreSecurityAlertsAnnounce() {
        let seen = RepoAlertRules.Seen(
            checksState: "SUCCESS", releaseTag: "v1", securityAlerts: 1, crashSignature: nil)
        let result = RepoAlertRules.gitHubAlerts(
            previous: seen, activity: facts(checks: "FAILURE", tag: "v2", security: 3), repoName: "InSync",
            enabled: all)
        XCTAssertEqual(result.alerts.map(\.kind), [.ci, .releases, .security])
        XCTAssertEqual(result.seen.checksState, "FAILURE")
    }

    func testAStillRedBuildAndDisabledKindsStayQuiet() {
        let seen = RepoAlertRules.Seen(checksState: "FAILURE", releaseTag: "v1", securityAlerts: 3, crashSignature: nil)
        let still = RepoAlertRules.gitHubAlerts(
            previous: seen, activity: facts(checks: "FAILURE", tag: "v1", security: 3), repoName: "InSync",
            enabled: all)
        XCTAssertTrue(still.alerts.isEmpty)

        let fine = RepoAlertRules.Seen(checksState: "SUCCESS", releaseTag: "v1", securityAlerts: 0, crashSignature: nil)
        let muted = RepoAlertRules.gitHubAlerts(
            previous: fine, activity: facts(checks: "FAILURE", tag: "v2", security: 2), repoName: "InSync",
            enabled: [.releases])
        XCTAssertEqual(muted.alerts.map(\.kind), [.releases])
    }

    func testCrashesNewerThanTheLastSeenOneAreCountedOnceEach() {
        func stats(_ dates: [TimeInterval]) -> RepoStats {
            RepoStats(
                schema: 1, app: "InSync", generatedAt: now, periodDays: 30,
                issues: dates.map {
                    RepoStats.Issue(
                        kind: "crash", title: "x", at: Date(timeIntervalSince1970: $0), count: 2,
                        version: nil, url: nil, status: nil)
                })
        }
        let first = RepoAlertRules.crashAlert(
            previous: nil, stats: stats([100, 200]), repoID: 1, repoName: "InSync", enabled: all)
        XCTAssertNil(first.alert)
        XCTAssertEqual(first.seen.crashSignature, String(TimeInterval(200)))

        let later = RepoAlertRules.crashAlert(
            previous: first.seen, stats: stats([200, 300, 400]), repoID: 1, repoName: "InSync", enabled: all)
        XCTAssertEqual(later.alert?.kind, .crashes)
        // Each of the two has `count: 2` lifetime hits; the alert says how many crashes are news.
        XCTAssertEqual(later.alert?.body, String(format: String(localized: "alert_crash_body_other %lld"), 2))
        XCTAssertEqual(later.seen.crashSignature, String(TimeInterval(400)))

        let same = RepoAlertRules.crashAlert(
            previous: later.seen, stats: stats([200, 300, 400]), repoID: 1, repoName: "InSync", enabled: all)
        XCTAssertNil(same.alert)
    }
}
