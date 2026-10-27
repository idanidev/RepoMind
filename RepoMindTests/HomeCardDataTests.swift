import SwiftData
import XCTest

@testable import RepoMind

// MARK: - Home card data

/// The redesigned home renders `HomeRepoCardData`, not models. These pin down the mapping from a
/// stored repo and the activity cache: which tasks count as pending, what earns a warning chip,
/// when a repo reads as inactive, and that two local projects never share a card id.
@MainActor
final class HomeCardDataTests: XCTestCase {
    /// Kept alive for the duration of a test; `makeContext()` hands out its main context.
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
    }

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: ProjectRepo.self, TaskItem.self, KanbanColumn.self, GitHubAccount.self, RepoFolder.self,
            configurations: config)
        self.container = container
        return container.mainContext
    }

    private func makeRepo(
        in context: ModelContext, name: String = "Sample", repoID: Int = 9_901
    ) -> ProjectRepo {
        let repo = ProjectRepo(
            repoID: repoID, name: name, htmlURL: "https://github.com/idanidev/\(name)")
        context.insert(repo)
        return repo
    }

    private func addColumn(
        _ name: String, order: Int, to repo: ProjectRepo, in context: ModelContext
    ) -> KanbanColumn {
        let column = KanbanColumn(name: name, orderIndex: order, project: repo)
        context.insert(column)
        return column
    }

    private func addTask(
        _ content: String, in column: KanbanColumn?, order: Int, to repo: ProjectRepo,
        context: ModelContext, needsIssueSync: Bool = false
    ) {
        let task = TaskItem(
            content: content, column: column, project: repo, orderIndex: order, needsIssueSync: needsIssueSync)
        context.insert(task)
    }

    private func activity(
        pushedDaysAgo days: Double? = nil, isPrivate: Bool = false, pullRequests: Int = 0,
        release: String? = nil, checks: String? = nil
    ) -> RepoActivity {
        RepoActivity(
            repoID: 9_901,
            pushedAt: days.map { Date.now.addingTimeInterval(-$0 * 86_400) },
            isPrivate: isPrivate,
            openPullRequests: pullRequests,
            latestReleaseTag: release,
            checksState: checks,
            fetchedAt: .now
        )
    }

    // MARK: Tasks

    func testPendingFollowsDoneColumnAndSkipsOrphans() throws {
        let context = try makeContext()
        let repo = makeRepo(in: context)
        let todo = addColumn("To Do", order: 0, to: repo, in: context)
        let done = addColumn("Done", order: 1, to: repo, in: context)
        for index in 0..<4 {
            addTask("Task \(index)", in: todo, order: index, to: repo, context: context)
        }
        addTask("Shipped", in: done, order: 0, to: repo, context: context)
        // An orphan: no column. OrphanTaskRepair reattaches these; the card must not count it.
        addTask("Lost", in: nil, order: 9, to: repo, context: context)
        try context.save()

        let card = HomeRepoCardData(repo: repo)

        XCTAssertEqual(card.tasksTotal, 5)
        XCTAssertEqual(card.tasksPending, 4)
        XCTAssertEqual(card.taskPreview.map(\.title), ["Task 0", "Task 1", "Task 2"])
    }

    func testNoTasksMeansNothingPending() throws {
        let context = try makeContext()
        let card = HomeRepoCardData(repo: makeRepo(in: context))
        XCTAssertEqual(card.tasksTotal, 0)
        XCTAssertEqual(card.tasksPending, 0)
        XCTAssertTrue(card.taskPreview.isEmpty)
    }

    // MARK: Warnings

    func testWarningsComeFromTheRepo() throws {
        let context = try makeContext()
        let repo = makeRepo(in: context)
        let todo = addColumn("To Do", order: 0, to: repo, in: context)
        addTask("Published", in: todo, order: 0, to: repo, context: context)
        addTask("Waiting", in: todo, order: 1, to: repo, context: context, needsIssueSync: true)
        addTask("Also waiting", in: todo, order: 2, to: repo, context: context, needsIssueSync: true)
        repo.syncTasksDisabledReason = "403"

        let card = HomeRepoCardData(repo: repo, unreadFeedback: 3)

        XCTAssertEqual(card.unpublished, 2)
        XCTAssertTrue(card.isSyncDisabled)
        XCTAssertEqual(card.alerts, 3)
        XCTAssertEqual(HomeRepoCardData(repo: makeRepo(in: context, name: "Quiet", repoID: 9_902)).alerts, 0)
    }

    // MARK: Activity

    func testActivityFillsWhatTheModelLacks() throws {
        let context = try makeContext()
        let repo = makeRepo(in: context)

        let bare = HomeRepoCardData(repo: repo)
        XCTAssertFalse(bare.isPrivate)
        XCTAssertNil(bare.pullRequests)
        XCTAssertNil(bare.version)
        XCTAssertFalse(bare.isBuildFailing)
        XCTAssertNil(bare.lastPush)

        let known = HomeRepoCardData(
            repo: repo,
            activity: activity(pushedDaysAgo: 1, isPrivate: true, pullRequests: 2, release: "v2.0.0", checks: "FAILURE")
        )
        XCTAssertTrue(known.isPrivate)
        XCTAssertEqual(known.pullRequests, 2)
        XCTAssertEqual(known.version, "v2.0.0")
        XCTAssertTrue(known.isBuildFailing)
        XCTAssertNotNil(known.lastPush)
    }

    func testInactiveComesFromArchiveOrSixQuietMonths() throws {
        let context = try makeContext()
        let repo = makeRepo(in: context)

        XCTAssertFalse(HomeRepoCardData(repo: repo).isInactive)
        XCTAssertFalse(HomeRepoCardData(repo: repo, activity: activity(pushedDaysAgo: 10)).isInactive)
        XCTAssertTrue(HomeRepoCardData(repo: repo, activity: activity(pushedDaysAgo: 200)).isInactive)

        repo.isArchived = true
        XCTAssertTrue(HomeRepoCardData(repo: repo, activity: activity(pushedDaysAgo: 1)).isInactive)
    }

    // MARK: Identity

    func testOwnerComesFromTheGitHubURL() throws {
        let context = try makeContext()
        let card = HomeRepoCardData(repo: makeRepo(in: context, name: "RepoMind"))
        XCTAssertEqual(card.owner, "idanidev")
        XCTAssertEqual(card.name, "RepoMind")
    }

    func testFolderIsCarriedOnTheCard() throws {
        let context = try makeContext()
        let repo = makeRepo(in: context)
        let folder = RepoFolder(name: "Web", colorHex: "#112233", orderIndex: 2)
        context.insert(folder)
        repo.folder = folder

        let card = HomeRepoCardData(repo: repo)

        XCTAssertEqual(card.folder?.name, "Web")
        XCTAssertEqual(card.folder?.colorHex, "#112233")
        XCTAssertEqual(card.folder?.orderIndex, 2)
        XCTAssertNil(HomeRepoCardData(repo: makeRepo(in: context, name: "Loose", repoID: 9_902)).folder)
    }

    func testTwoLocalProjectsWithTheSameNameGetDistinctCardIDs() throws {
        let context = try makeContext()
        let first = makeRepo(in: context, name: "Notes", repoID: 0)
        first.isLocal = true
        let second = makeRepo(in: context, name: "Notes", repoID: 0)
        second.isLocal = true
        try context.save()

        XCTAssertNotEqual(first.homeCardID, second.homeCardID)
        XCTAssertNotEqual(HomeRepoCardData(repo: first).id, HomeRepoCardData(repo: second).id)
    }

    // MARK: Filters and stats

    func testFiltersKeepFavoritesAndPendingWork() {
        let favorite = HomeRepoCardData(id: "a", name: "A", isFavorite: true)
        let busy = HomeRepoCardData(id: "b", name: "B", tasksTotal: 2, tasksPending: 1)
        let idle = HomeRepoCardData(id: "c", name: "C", tasksTotal: 2, tasksPending: 0)
        let archived = HomeRepoCardData(
            id: "d", name: "D", isFavorite: true, isArchived: true, tasksTotal: 1, tasksPending: 1)
        let all = [favorite, busy, idle, archived]

        XCTAssertEqual(HomeFilter.all.apply(to: all).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(HomeFilter.favorites.apply(to: all).map(\.id), ["a"])
        XCTAssertEqual(HomeFilter.tasks.apply(to: all).map(\.id), ["b"])
        XCTAssertEqual(HomeFilter.archived.apply(to: all).map(\.id), ["d"])
    }

    func testStatsSumTheCards() {
        let stats = HomeStats(cards: HomeMockData.repos)
        XCTAssertEqual(stats.totalRepos, 6)
        XCTAssertEqual(stats.pendingTasks, 8)
        XCTAssertEqual(stats.alerts, 2)
        XCTAssertEqual(stats.unpublished, 1)
    }

    func testMockDataIsConsistent() {
        let ids = HomeMockData.repos.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(HomeMockData.repos.filter(\.isFeatured).count, 1)
    }
}
