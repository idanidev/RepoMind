import XCTest

@testable import RepoMind

@MainActor
final class StoreStatusTests: XCTestCase {
    private let sample = """
        {
          "schema": 1,
          "generatedAt": "2026-10-27T06:31:00Z",
          "apps": [
            {
              "id": "6740000000",
              "name": "RepoMind: Kanban for GitHub",
              "bundleId": "idanidev.RepoMind",
              "repo": "RepoMind",
              "versions": [
                { "platform": "IOS", "version": "1.5.3", "state": "WAITING_FOR_REVIEW",
                  "createdAt": "2026-10-20T10:00:00-07:00" },
                { "platform": "IOS", "version": "1.5.2", "state": "READY_FOR_SALE",
                  "createdAt": "2026-09-01T09:00:00-07:00" },
                { "platform": "IOS", "version": "1.5.0", "state": "PREPARE_FOR_SUBMISSION",
                  "createdAt": "2026-08-10T09:00:00-07:00" },
                { "platform": "MAC_OS", "version": "1.4.0", "state": "READY_FOR_SALE",
                  "createdAt": "2026-07-01T09:00:00-07:00" }
              ],
              "builds": [
                { "version": "1.5.3", "build": "202610270821", "uploadedAt": "2026-10-27T08:24:00Z",
                  "state": "VALID", "expired": false }
              ],
              "sales": {
                "through": "2026-10-25",
                "daily": [
                  { "date": "2026-10-23", "downloads": 1, "updates": 5, "purchases": 0 },
                  { "date": "2026-10-24", "downloads": 2, "updates": 7, "purchases": 1 },
                  { "date": "2026-10-25", "downloads": 3, "updates": 12, "purchases": 0 }
                ]
              }
            }
          ]
        }
        """

    private func decoded() throws -> StoreStatus.StoreApp {
        try XCTUnwrap(StoreStatus.decode(Data(sample.utf8)).apps.first)
    }

    private func version(_ number: String, _ state: String, platform: String = "IOS") -> StoreStatus.Version {
        StoreStatus.Version(platform: platform, version: number, state: state, createdAt: nil)
    }

    private func build(_ number: String, version: String?, state: String? = "VALID", expired: Bool = false)
        -> StoreStatus.Build {
        StoreStatus.Build(version: version, build: number, uploadedAt: nil, state: state, expired: expired)
    }

    // MARK: Decoding

    func testTheContractsExampleDecodes() throws {
        let status = try StoreStatus.decode(Data(sample.utf8))
        XCTAssertEqual(status.apps.count, 1)
        let app = try XCTUnwrap(status.apps.first)
        XCTAssertEqual(app.repo, "RepoMind")
        XCTAssertEqual(app.versions.count, 4)
        XCTAssertEqual(app.builds.first?.build, "202610270821")
        XCTAssertEqual(app.sales?.daily.count, 3)
        XCTAssertNotNil(app.versions.first?.createdAt)
    }

    func testAVersionWithoutAStateAndABuildWithoutExpiredStillDecode() throws {
        // The workflow writes `state: null` when Apple sends neither attribute, and a build may not say
        // `expired`: both used to refuse the whole file.
        let json = """
            {"schema":1,"generatedAt":"2026-10-27T09:00:00Z","apps":[
              {"id":"1","name":"A","bundleId":"x.y","versions":[
                 {"platform":"IOS","version":"1.0","state":null,"createdAt":"2026-10-01T09:00:00Z"},
                 {"platform":"IOS","version":"1.1","state":"READY_FOR_DISTRIBUTION"},
                 {"platform":"IOS"}],
               "builds":[{"version":"1.1","build":"202610270821","state":"VALID"}]},
              {"broken":true}]}
            """
        let status = try StoreStatus.decode(Data(json.utf8))

        XCTAssertEqual(status.apps.count, 1, "the app that is not an app is dropped, not the file")
        let app = try XCTUnwrap(status.apps.first)
        XCTAssertEqual(app.versions.map(\.kind), [.other, .live])
        XCTAssertEqual(app.builds.first?.expired, false)
        XCTAssertNotNil(app.latestBuild)
    }

    func testBothNamesOfThePublishedStateMeanLive() {
        XCTAssertEqual(StoreVersionState(raw: "READY_FOR_SALE"), .live)
        // What `appVersionState`, which the workflow prefers, calls it.
        XCTAssertEqual(StoreVersionState(raw: "READY_FOR_DISTRIBUTION"), .live)
        XCTAssertEqual(StoreVersionState(raw: "PREORDER_READY_FOR_SALE"), .approved)
        XCTAssertEqual(StoreVersionState(raw: ""), .other)
    }

    func testAFileThatStoppedBeingWrittenIsStale() {
        let now = Date.now
        XCTAssertFalse(StoreStatus(schema: 1, generatedAt: now.addingTimeInterval(-20 * 3600)).isStale(now: now))
        XCTAssertTrue(StoreStatus(schema: 1, generatedAt: now.addingTimeInterval(-37 * 3600)).isStale(now: now))
    }

    func testTheLongestRepoNameThatFitsIsTheAppsRepo() {
        let app = StoreStatus.StoreApp(id: "1", name: "RepoMind: Kanban for GitHub", bundleId: "idanidev.RepoMind")
        XCTAssertEqual(app.bestRepoName(in: ["Repo", "RepoMind", "InSync"]), "RepoMind")
        XCTAssertEqual(app.bestRepoName(in: ["InSync"]), nil)
        XCTAssertEqual(app.bestRepoName(in: []), nil)
    }

    func testAnUnknownSchemaIsRefusedWhole() {
        let future = sample.replacingOccurrences(of: "\"schema\": 1", with: "\"schema\": 2")
        XCTAssertThrowsError(try StoreStatus.decode(Data(future.utf8)))
        XCTAssertThrowsError(try StoreStatus.decode(Data("not json".utf8)))
    }

    func testAnAppWithoutVersionsBuildsOrSalesStillDecodes() throws {
        let json = """
            { "schema": 1, "generatedAt": "2026-10-27T06:31:00Z",
              "apps": [ { "id": "1", "name": "Bare", "bundleId": "x.bare" } ] }
            """
        let app = try XCTUnwrap(StoreStatus.decode(Data(json.utf8)).apps.first)
        XCTAssertTrue(app.versions.isEmpty)
        XCTAssertTrue(app.builds.isEmpty)
        XCTAssertNil(app.sales)
        XCTAssertNil(app.downloads)
        XCTAssertTrue(app.releases.isEmpty)
    }

    // MARK: States

    func testAppleStatesMapToTheCasesTheAppTellsApart() {
        XCTAssertEqual(StoreVersionState(raw: "READY_FOR_SALE"), .live)
        XCTAssertEqual(StoreVersionState(raw: "IN_REVIEW"), .inReview)
        XCTAssertEqual(StoreVersionState(raw: "PENDING_DEVELOPER_RELEASE"), .approved)
        XCTAssertEqual(StoreVersionState(raw: "METADATA_REJECTED"), .rejected)
        XCTAssertEqual(StoreVersionState(raw: "PREPARE_FOR_SUBMISSION"), .draft)
        XCTAssertEqual(StoreVersionState(raw: "REPLACED_WITH_NEW_VERSION"), .replaced)
        XCTAssertEqual(StoreVersionState(raw: "SOMETHING_APPLE_ADDS_NEXT_YEAR"), .other)
        XCTAssertTrue(StoreVersionState.waitingForReview.isPending)
        XCTAssertFalse(StoreVersionState.live.isPending)
        XCTAssertFalse(StoreVersionState.replaced.isPending)
    }

    // MARK: Which one is published

    func testLiveAndPendingAreToldApartPerPlatform() throws {
        let app = try decoded()
        let ios = try XCTUnwrap(app.releases.first { $0.platform == "IOS" })
        XCTAssertEqual(ios.live?.version, "1.5.2")
        XCTAssertEqual(ios.pending?.version, "1.5.3")
        let mac = try XCTUnwrap(app.releases.first { $0.platform == "MAC_OS" })
        XCTAssertEqual(mac.live?.version, "1.4.0")
        XCTAssertNil(mac.pending)
        XCTAssertEqual(mac.platformName, "macOS")
        XCTAssertEqual(app.primaryRelease?.platform, "IOS")
    }

    func testADraftOlderThanTheLiveVersionIsLeftoverNotNews() throws {
        // 1.5.0 is still "prepare for submission" in the list but 1.5.2 is out and newer.
        let app = StoreStatus.StoreApp(
            id: "1", name: "A", bundleId: "a",
            versions: [version("1.5.2", "READY_FOR_SALE"), version("1.5.0", "PREPARE_FOR_SUBMISSION")])
        XCTAssertNil(app.primaryRelease?.pending)
        XCTAssertEqual(app.primaryRelease?.live?.version, "1.5.2")
    }

    func testAnAppNeverPublishedHasNoLiveVersionButAPendingOne() {
        let app = StoreStatus.StoreApp(
            id: "1", name: "A", bundleId: "a", versions: [version("1.0", "IN_REVIEW")])
        XCTAssertNil(app.primaryRelease?.live)
        XCTAssertEqual(app.primaryRelease?.pending?.version, "1.0")
    }

    // MARK: A build nobody sent

    func testABuildNewerThanTheLiveOneAndNotInReviewIsUnsent() {
        let app = StoreStatus.StoreApp(
            id: "1", name: "A", bundleId: "a",
            versions: [version("1.5.2", "READY_FOR_SALE")], builds: [build("9", version: "1.5.3")])
        XCTAssertEqual(app.unsubmittedBuild?.build, "9")
    }

    func testABuildOfTheVersionInReviewOrAlreadyLiveIsNotUnsent() {
        let inReview = StoreStatus.StoreApp(
            id: "1", name: "A", bundleId: "a",
            versions: [version("1.5.3", "IN_REVIEW"), version("1.5.2", "READY_FOR_SALE")],
            builds: [build("9", version: "1.5.3")])
        XCTAssertNil(inReview.unsubmittedBuild)

        let live = StoreStatus.StoreApp(
            id: "1", name: "A", bundleId: "a",
            versions: [version("1.5.2", "READY_FOR_SALE")], builds: [build("8", version: "1.5.2")])
        XCTAssertNil(live.unsubmittedBuild)
    }

    func testAnExpiredOrInvalidBuildIsNeverTheLatest() {
        let app = StoreStatus.StoreApp(
            id: "1", name: "A", bundleId: "a",
            versions: [version("1.5.2", "READY_FOR_SALE")],
            builds: [build("10", version: "1.5.4", expired: true), build("9", version: "1.5.3", state: "INVALID"),
                build("8", version: "1.5.3")])
        XCTAssertEqual(app.latestBuild?.build, "8")
    }

    func testVersionsCompareNumerically() {
        XCTAssertTrue(StoreStatus.isNewer("1.5.10", than: "1.5.9"))
        XCTAssertTrue(StoreStatus.isNewer("1.6", than: "1.5.9"))
        XCTAssertFalse(StoreStatus.isNewer("1.5", than: "1.5.0"))
        XCTAssertFalse(StoreStatus.isNewer("1.5.2", than: "1.5.3"))
    }

    // MARK: Which repo it is

    func testTheMapWinsAndOtherwiseTheNameOrTheBundleIdDecide() {
        let mapped = StoreStatus.StoreApp(id: "1", name: "Calendar for couples", bundleId: "com.x.sync", repo: "InSync")
        XCTAssertTrue(mapped.matches(repoName: "insync"))
        XCTAssertFalse(mapped.matches(repoName: "RepoMind"))

        let guessed = StoreStatus.StoreApp(id: "2", name: "RepoMind: Kanban for GitHub", bundleId: "idanidev.RepoMind")
        XCTAssertTrue(guessed.matches(repoName: "RepoMind"))
        XCTAssertTrue(guessed.matches(repoName: "repo-mind"))
        XCTAssertFalse(guessed.matches(repoName: "InSync"))
        XCTAssertFalse(guessed.matches(repoName: "ab"), "a name that short matches everything")
    }

    // MARK: Downloads

    func testDownloadsAddUpOverTheLastDays() throws {
        let downloads = try XCTUnwrap(decoded().downloads)
        XCTAssertEqual(downloads.last7, 6)
        XCTAssertEqual(downloads.last30, 6)
        XCTAssertEqual(downloads.downloads(lastDays: 1), 3)
        XCTAssertEqual(downloads.updates(lastDays: 2), 19)
        XCTAssertEqual(downloads.purchases(lastDays: 30), 1)
        XCTAssertEqual(downloads.sparkline, [1, 2, 3])
        XCTAssertTrue(downloads.hasActivity)
        XCTAssertNotNil(downloads.through)
    }

    func testAnAppWithNoSalesIsNotDrawnAsAFlatLine() {
        let sales = StoreStatus.Sales(
            through: "2026-10-25", daily: [StoreStatus.Day(date: "2026-10-25", downloads: 0, updates: 0, purchases: 0)])
        XCTAssertFalse(StoreDownloads(sales: sales).hasActivity)
    }

    // MARK: The home's row

    func testTheHomeRowUsesTheReposNameWhenThereIsOne() throws {
        let app = try decoded()
        let repo = ProjectRepo(repoID: 7, name: "RepoMind", htmlURL: "https://github.com/idanidev/RepoMind")
        let linked = HomeStoreApp(app: app, repos: [repo])
        XCTAssertEqual(linked.name, "RepoMind")
        XCTAssertEqual(linked.repoCardID, repo.homeCardID)
        XCTAssertNil(linked.unsubmitted)

        let alone = HomeStoreApp(app: app, repos: [])
        XCTAssertEqual(alone.name, "RepoMind: Kanban for GitHub")
        XCTAssertNil(alone.repoCardID)
        XCTAssertEqual(alone.releases.count, 2)
    }
}
