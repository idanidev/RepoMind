import SwiftData
import XCTest

@testable import RepoMind

// MARK: - GraphQL document and parser

final class RepoActivityQueryTests: XCTestCase {
    func testDocumentAliasesEveryRepoAndDropsInvalidNames() {
        let document = RepoActivityQuery.document(for: [
            (owner: "idanidev", name: "RepoMind"),
            (owner: "bad owner", name: "x\"y"),
            (owner: "idanidev", name: "in.sync-2")
        ])

        XCTAssertTrue(document.contains("r0: repository(owner: \"idanidev\", name: \"RepoMind\")"))
        XCTAssertTrue(document.contains("r2: repository(owner: \"idanidev\", name: \"in.sync-2\")"))
        XCTAssertFalse(document.contains("r1:"))
        XCTAssertFalse(document.contains("bad owner"))
        XCTAssertTrue(document.contains("fragment activity on Repository"))
    }

    func testDocumentIsEmptyWhenNoRepoHasAUsableName() {
        XCTAssertEqual(RepoActivityQuery.document(for: [(owner: "", name: "x")]), "")
        XCTAssertEqual(RepoActivityQuery.document(for: []), "")
    }

    func testParseReadsEveryFieldAndSkipsUnresolvedRepos() throws {
        let json = """
        {"data":{"r0":{"databaseId":42,"pushedAt":"2026-10-20T10:00:00Z","isPrivate":true,
        "pullRequests":{"totalCount":2},"latestRelease":{"tagName":"v1.2.0"},
        "defaultBranchRef":{"target":{"statusCheckRollup":{"state":"FAILURE"}}}},
        "r1":null},"errors":[{"message":"Could not resolve to a Repository"}]}
        """

        let activities = try RepoActivityQuery.parse(Data(json.utf8))

        XCTAssertEqual(activities.count, 1)
        let activity = try XCTUnwrap(activities.first)
        XCTAssertEqual(activity.repoID, 42)
        XCTAssertTrue(activity.isPrivate)
        XCTAssertEqual(activity.openPullRequests, 2)
        XCTAssertEqual(activity.latestReleaseTag, "v1.2.0")
        XCTAssertTrue(activity.isBuildFailing)
        XCTAssertEqual(activity.pushedAt, ISO8601DateFormatter().date(from: "2026-10-20T10:00:00Z"))
    }

    func testParseToleratesReposWithoutChecksOrReleases() throws {
        let json = """
        {"data":{"r0":{"databaseId":7,"pushedAt":null,"isPrivate":false,"pullRequests":{"totalCount":0},
        "latestRelease":null,"defaultBranchRef":null}}}
        """

        let activity = try XCTUnwrap(RepoActivityQuery.parse(Data(json.utf8)).first)

        XCTAssertEqual(activity.repoID, 7)
        XCTAssertNil(activity.pushedAt)
        XCTAssertNil(activity.latestReleaseTag)
        XCTAssertNil(activity.checksState)
        XCTAssertFalse(activity.isBuildFailing)
    }

    func testParseThrowsWhenGitHubRejectsTheWholeQuery() {
        // GitHub sends a rate limit or bad credentials as a 200 with `errors` and no `data`. Reading
        // that as "no repo has activity" would stamp the refresh as done and mute the next hour.
        let json = """
        {"errors":[{"message":"Bad credentials"}]}
        """
        XCTAssertThrowsError(try RepoActivityQuery.parse(Data(json.utf8)))
    }

    func testParseKeepsTheRestOfABatchWhenOneRepoCannotBeResolved() throws {
        let json = """
        {"data":{"r0":null,"r1":{"databaseId":9,"pushedAt":null,"isPrivate":true,"pullRequests":{"totalCount":1},
        "latestRelease":null,"defaultBranchRef":null}},"errors":[{"message":"Could not resolve to a Repository"}]}
        """
        let parsed = try RepoActivityQuery.parse(Data(json.utf8))
        XCTAssertEqual(parsed.map(\.repoID), [9])
    }

    func testParseOfAnEmptyObjectIsNotAFailure() throws {
        XCTAssertTrue(try RepoActivityQuery.parse(Data("{}".utf8)).isEmpty)
    }

    func testBuildFailingCoversErrorToo() {
        let base = RepoActivity(repoID: 1, fetchedAt: .now)
        XCTAssertFalse(base.isBuildFailing)
        var failing = base
        failing.checksState = "ERROR"
        XCTAssertTrue(failing.isBuildFailing)
        failing.checksState = "SUCCESS"
        XCTAssertFalse(failing.isBuildFailing)
    }
}

// MARK: - Store

@MainActor
final class RepoActivityStoreTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
    }

    func testStartsStaleAndEmptyWithoutACache() {
        // The standard defaults of the test host, with the cache key cleared: a `suiteName`
        // defaults crashed the simulator's test host on CI at this exact point.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "repoActivityCache")
        let store = RepoActivityStore(defaults: defaults)

        XCTAssertTrue(store.isStale)
        XCTAssertNil(store.lastRefresh)
        XCTAssertNil(store.activity(for: 1))
    }

    func testTargetsSkipLocalProjectsAndReposWithoutAnOwner() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: ProjectRepo.self, TaskItem.self, KanbanColumn.self, GitHubAccount.self,
            configurations: config)
        self.container = container
        let context = container.mainContext

        let account = GitHubAccount(username: "idanidev", tokenKey: "k1")
        context.insert(account)
        let github = ProjectRepo(repoID: 1, name: "RepoMind", htmlURL: "https://github.com/idanidev/RepoMind")
        github.account = account
        let local = ProjectRepo(repoID: 0, name: "Notes", isLocal: true)
        local.account = account
        let noURL = ProjectRepo(repoID: 2, name: "Mystery")
        noURL.account = account
        for repo in [github, local, noURL] { context.insert(repo) }

        let targets = RepoActivityStore.targets(repos: [github, local, noURL], accounts: [account])

        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.account.username, "idanidev")
        XCTAssertEqual(targets.first?.repos.map(\.name), ["RepoMind"])
        XCTAssertEqual(targets.first?.repos.map(\.owner), ["idanidev"])
    }

    func testTargetsAreEmptyWithoutAccounts() {
        XCTAssertTrue(RepoActivityStore.targets(repos: [], accounts: []).isEmpty)
    }
}
