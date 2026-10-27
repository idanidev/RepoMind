import SwiftData
import XCTest

@testable import RepoMind

@MainActor
final class HomeDigestTests: XCTestCase {
    private var container: ModelContainer?
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func tearDown() {
        container = nil
        UserDefaults.standard.removeObject(forKey: "ideaColumnID_7")
    }

    private func day(_ days: Double) -> Date { now.addingTimeInterval(-days * 24 * 60 * 60) }

    /// A repo with To Do, Ideas and Done, and one task in each shape the digest tells apart.
    private func makeRepo() throws -> ProjectRepo {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: ProjectRepo.self, TaskItem.self, KanbanColumn.self, GitHubAccount.self,
            configurations: config)
        self.container = container
        let context = container.mainContext

        let repo = ProjectRepo(repoID: 7, name: "InSync", htmlURL: "https://github.com/idanidev/InSync")
        context.insert(repo)
        let todo = KanbanColumn(name: "To Do", orderIndex: 0, project: repo)
        let ideas = KanbanColumn(name: "Ideas", orderIndex: 1, project: repo)
        let done = KanbanColumn(name: "Done", orderIndex: 2, project: repo)
        [todo, ideas, done].forEach(context.insert)
        repo.columns = [todo, ideas, done]
        UserDefaults.standard.set(ideas.id.uuidString, forKey: "ideaColumnID_7")

        func add(_ content: String, in column: KanbanColumn, daysAgo: Double, error: String? = nil) {
            let task = TaskItem(content: content, column: column, project: repo)
            task.createdAt = day(daysAgo)
            task.lastSyncError = error
            task.needsIssueSync = error != nil
            context.insert(task)
        }
        add("old pending", in: todo, daysAgo: 20)
        add("older pending", in: todo, daysAgo: 40)
        add("fresh pending", in: todo, daysAgo: 2)
        add("old idea", in: ideas, daysAgo: 60)
        add("old done", in: done, daysAgo: 60)
        add("stuck", in: todo, daysAgo: 3, error: "401")
        try context.save()
        return repo
    }

    func testAbandonedAreOldPendingWorkOnly() throws {
        let repo = try makeRepo()
        let abandoned = HomeDigest.abandonedTasks(in: [repo], now: now)
        XCTAssertEqual(abandoned.map(\.content), ["older pending", "old pending"])
    }

    func testDigestCountsThroughTheSameFunctions() throws {
        let repo = try makeRepo()
        let digest = HomeDigest(
            repos: [repo], unreadFeedback: 3,
            activity: { _ in
                RepoActivity(
                    repoID: 7, pushedAt: self.day(45), isPrivate: true, openPullRequests: 2,
                    latestReleaseTag: nil, checksState: "FAILURE", fetchedAt: self.now)
            },
            stats: { _ in nil },
            now: now)

        XCTAssertEqual(digest.abandoned, 2)
        XCTAssertEqual(digest.syncErrors, 1)
        XCTAssertEqual(digest.unpublished, 1)
        XCTAssertEqual(digest.failingBuilds, 1)
        XCTAssertEqual(digest.pullRequests, 2)
        XCTAssertEqual(digest.unreadFeedback, 3)
        XCTAssertEqual(digest.dormantRepos, 1, "pending work and no push in 45 days")
        XCTAssertEqual(digest.capturedThisWeek, 2, "the fresh task and the stuck one")
        XCTAssertFalse(digest.isQuiet)
    }

    func testDormantNeedsAPushDateAndPendingWork() throws {
        let repo = try makeRepo()
        XCTAssertTrue(HomeDigest.dormantRepos(in: [repo], activity: { _ in nil }, now: now).isEmpty)

        let recent = RepoActivity(repoID: 7, pushedAt: day(3), fetchedAt: now)
        XCTAssertTrue(HomeDigest.dormantRepos(in: [repo], activity: { _ in recent }, now: now).isEmpty)

        let stale = RepoActivity(repoID: 7, pushedAt: day(45), fetchedAt: now)
        XCTAssertEqual(HomeDigest.dormantRepos(in: [repo], activity: { _ in stale }, now: now).count, 1)
    }

    func testArchivedReposAndQuietAccountsStayOut() throws {
        let repo = try makeRepo()
        repo.isArchived = true
        let digest = HomeDigest(
            repos: [repo], unreadFeedback: 0, activity: { _ in nil }, stats: { _ in nil }, now: now)
        XCTAssertTrue(digest.isQuiet)
        XCTAssertEqual(digest.capturedThisWeek, 0)
    }

    func testAppRowComesFromThePrimaryHeadline() throws {
        let repo = try makeRepo()
        let stats = RepoStats(
            schema: 1, app: "InSync", generatedAt: now, periodDays: 30,
            headline: [
                RepoStats.Headline(key: "active_day", label: "Activas hoy", value: 12, previous: nil, primary: nil),
                RepoStats.Headline(key: "active_week", label: "Activas 7 días", value: 31, previous: 25, primary: true),
            ],
            issues: [
                RepoStats.Issue(kind: "crash", title: "a", at: now, count: 3, version: nil, url: nil, status: nil),
                RepoStats.Issue(kind: "report", title: "b", at: now, count: 1, version: nil, url: nil, status: nil),
            ])
        let app = try XCTUnwrap(HomeDigestApp(repo: repo, stats: stats))
        XCTAssertEqual(app.headline, "31 Activas 7 días")
        XCTAssertEqual(try XCTUnwrap(app.change), 0.24, accuracy: 0.0001)
        XCTAssertEqual(app.crashes, 1)
        XCTAssertEqual(app.reports, 1)

        var silent = stats
        silent.headline = []
        XCTAssertNil(HomeDigestApp(repo: repo, stats: silent))
    }
}
