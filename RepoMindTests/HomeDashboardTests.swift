import SwiftData
import XCTest

@testable import RepoMind

@MainActor
final class HomeDashboardTests: XCTestCase {
    private var container: ModelContainer?
    /// Midday UTC, so "today" means the same day in every time zone a runner may sit in.
    private let now = Date(timeIntervalSince1970: 1_800_043_200)

    override func tearDown() {
        container = nil
        UserDefaults.standard.removeObject(forKey: "ideaColumnID_9")
    }

    private func day(_ days: Double) -> Date { now.addingTimeInterval(-days * 24 * 60 * 60) }

    private func makeRepo() throws -> ProjectRepo {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: ProjectRepo.self, TaskItem.self, KanbanColumn.self, GitHubAccount.self, RepoFolder.self,
            configurations: config)
        self.container = container
        let context = container.mainContext

        let repo = ProjectRepo(
            repoID: 9, name: "InSync", htmlURL: "https://github.com/idanidev/InSync", language: "Swift")
        context.insert(repo)
        let todo = KanbanColumn(name: "To Do", orderIndex: 0, project: repo)
        let ideas = KanbanColumn(name: "Ideas", orderIndex: 1, project: repo)
        let done = KanbanColumn(name: "Done", orderIndex: 2, project: repo)
        [todo, ideas, done].forEach(context.insert)
        repo.columns = [todo, ideas, done]
        UserDefaults.standard.set(ideas.id.uuidString, forKey: "ideaColumnID_9")

        func add(_ content: String, in column: KanbanColumn, daysAgo: Double) {
            let task = TaskItem(content: content, column: column, project: repo)
            task.createdAt = day(daysAgo)
            context.insert(task)
        }
        add("today", in: todo, daysAgo: 0.1)
        add("this week", in: todo, daysAgo: 3)
        add("old pending", in: todo, daysAgo: 20)
        add("idea", in: ideas, daysAgo: 1)
        add("done", in: done, daysAgo: 2)
        try context.save()
        return repo
    }

    private func data(
        _ repo: ProjectRepo, activity: RepoActivity? = nil, stats: RepoStats? = nil
    ) -> HomeDashboardData {
        HomeDashboardData(
            repos: [repo], accounts: [], folders: 2, unreadFeedback: 1,
            activity: { _ in activity }, stats: { _ in stats },
            sync: HomeSyncStatus(), isPro: true, now: now)
    }

    func testTotalsCountWorkDoneAndIdeasApart() throws {
        let totals = try data(makeRepo()).tasks
        XCTAssertEqual(totals.total, 5)
        XCTAssertEqual(totals.pending, 3)
        XCTAssertEqual(totals.done, 1)
        XCTAssertEqual(totals.ideas, 1)
        XCTAssertEqual(totals.capturedToday, 1)
        XCTAssertEqual(totals.capturedWeek, 4)
        XCTAssertEqual(totals.doneRatio, 0.25, accuracy: 0.0001)
    }

    func testHistoryCoversFourteenDaysOldestFirst() throws {
        let history = try data(makeRepo()).captureHistory
        XCTAssertEqual(history.count, HomeDashboardData.historyDays)
        XCTAssertTrue(try XCTUnwrap(history.first).date < XCTUnwrap(history.last).date)
        XCTAssertEqual(history.reduce(0) { $0 + $1.count }, 4, "everything but the task from 20 days ago")
    }

    func testRecentAreNewestFirstAndBusiestCountsWork() throws {
        let repo = try makeRepo()
        let data = data(repo)
        XCTAssertEqual(data.recent.map(\.title), ["today", "idea", "done", "this week", "old pending"])
        XCTAssertEqual(data.recent.first?.repoCardID, repo.homeCardID)
        XCTAssertTrue(data.recent[2].isDone)
        XCTAssertEqual(data.busiest.count, 1)
        XCTAssertEqual(data.busiest.first?.pending, 3)
        XCTAssertEqual(data.busiest.first?.total, 4, "ideas are not work")
    }

    func testGitHubSummaryWaitsForActivity() throws {
        let repo = try makeRepo()
        XCTAssertEqual(data(repo).github.known, 0)

        let facts = RepoActivity(
            repoID: 9, pushedAt: day(0.5), isPrivate: true, openPullRequests: 2,
            latestReleaseTag: "v1.0.12", checksState: "FAILURE", fetchedAt: now)
        let github = data(repo, activity: facts).github
        XCTAssertEqual(github.known, 1)
        XCTAssertEqual(github.pushedToday, 1)
        XCTAssertEqual(github.pushedWeek, 1)
        XCTAssertEqual(github.openPullRequests, 2)
        XCTAssertEqual(github.failing, ["InSync"])
        XCTAssertEqual(github.privateRepos, 1)
        XCTAssertEqual(github.recentPushes.map(\.name), ["InSync"])
        XCTAssertEqual(github.releases.map(\.tag), ["v1.0.12"])
    }

    func testLanguagesCountsAndAppSummary() throws {
        let repo = try makeRepo()
        let stats = RepoStats(
            schema: 1, app: "InSync", generatedAt: now, periodDays: 30,
            headline: [
                RepoStats.Headline(
                    key: "active_week", label: "Activas 7 días", value: 31, previous: 25, primary: true),
                RepoStats.Headline(key: "accounts", label: "Cuentas", value: 128, previous: nil, primary: nil),
                RepoStats.Headline(key: "empty", label: "Vacía", value: nil, previous: nil, primary: nil),
            ],
            series: [RepoStats.Series(key: "app.abierta", label: "Aperturas", points: [
                RepoStats.Point(date: "2026-10-01", value: 4), RepoStats.Point(date: "2026-10-02", value: 7),
            ])])
        let data = data(repo, stats: stats)

        XCTAssertEqual(data.languages.map(\.name), ["Swift"])
        XCTAssertEqual(data.apps.count, 1)
        let app = try XCTUnwrap(data.apps.first)
        XCTAssertEqual(app.app.headline, "31 Activas 7 días")
        XCTAssertEqual(app.headlines.map(\.label), ["Cuentas"], "the primary and the empty one stay out")
        XCTAssertEqual(app.sparkline, [4, 7])
        XCTAssertEqual(data.repos.folders, 2)
        XCTAssertEqual(data.digest.unreadFeedback, 1)
    }
}
