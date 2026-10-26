import SwiftData
import XCTest

@testable import RepoMind

// MARK: - Home card data

/// The redesigned home renders `HomeRepoCardData`, not models. These pin down the mapping from a
/// stored repo: which tasks count as pending, what the badge says, and that two local projects
/// never share a card id.
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
            for: ProjectRepo.self, TaskItem.self, KanbanColumn.self, GitHubAccount.self,
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
        _ content: String, in column: KanbanColumn?, order: Int, to repo: ProjectRepo, context: ModelContext
    ) {
        let task = TaskItem(content: content, column: column, project: repo, orderIndex: order)
        context.insert(task)
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
        XCTAssertEqual(try XCTUnwrap(card.progress), 0.2, accuracy: 0.001)
    }

    func testNoTasksMeansNoProgress() throws {
        let context = try makeContext()
        let card = HomeRepoCardData(repo: makeRepo(in: context))
        XCTAssertEqual(card.tasksTotal, 0)
        XCTAssertNil(card.progress)
        XCTAssertTrue(card.taskPreview.isEmpty)
    }

    // MARK: Identity and badges

    func testOwnerComesFromTheGitHubURL() throws {
        let context = try makeContext()
        let card = HomeRepoCardData(repo: makeRepo(in: context, name: "RepoMind"))
        XCTAssertEqual(card.owner, "idanidev")
        XCTAssertEqual(card.name, "RepoMind")
    }

    func testStatusReflectsArchivedAndLocal() throws {
        let context = try makeContext()
        let archived = makeRepo(in: context, name: "Old", repoID: 9_902)
        archived.isArchived = true
        let local = makeRepo(in: context, name: "Local", repoID: 0)
        local.isLocal = true
        let plain = makeRepo(in: context, name: "Plain", repoID: 9_903)

        XCTAssertEqual(HomeRepoCardData(repo: archived).status, .inactive)
        XCTAssertEqual(HomeRepoCardData(repo: local).status, .inDevelopment)
        XCTAssertNil(HomeRepoCardData(repo: plain).status)
    }

    func testAlertsOnlyWhenThereIsUnreadFeedback() throws {
        let context = try makeContext()
        let repo = makeRepo(in: context)
        XCTAssertNil(HomeRepoCardData(repo: repo).alerts)
        XCTAssertEqual(HomeRepoCardData(repo: repo, unreadFeedback: 2).alerts, 2)
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

    // MARK: Filters

    func testFiltersKeepFavoritesAndPendingWork() {
        let favorite = HomeRepoCardData(id: "a", name: "A", isFavorite: true)
        let busy = HomeRepoCardData(id: "b", name: "B", tasksTotal: 2, tasksPending: 1)
        let idle = HomeRepoCardData(id: "c", name: "C", tasksTotal: 2, tasksPending: 0)
        let all = [favorite, busy, idle]

        XCTAssertEqual(HomeFilter.all.apply(to: all).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(HomeFilter.favorites.apply(to: all).map(\.id), ["a"])
        XCTAssertEqual(HomeFilter.tasks.apply(to: all).map(\.id), ["b"])
    }

    func testMockDataIsConsistent() {
        let ids = HomeMockData.repos.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(HomeMockData.repos.filter(\.isFeatured).count, 1)
        XCTAssertEqual(HomeMockData.repos.filter(\.isOwnApp).count, 1)
        XCTAssertEqual(HomeMockData.repos.count, HomeMockData.stats.totalRepos)
    }
}
