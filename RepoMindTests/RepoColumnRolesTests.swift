import SwiftData
import XCTest

@testable import RepoMind

@MainActor
final class RepoColumnRolesTests: XCTestCase {
    private struct Board {
        let context: ModelContext
        let repo: ProjectRepo
        let todo: KanbanColumn
        let ideas: KanbanColumn
        let done: KanbanColumn

        func task(_ title: String, in column: KanbanColumn?) -> TaskItem {
            let item = TaskItem(content: title, status: "x", column: column, project: repo, orderIndex: 0)
            context.insert(item)
            return item
        }
    }

    private var container: ModelContainer?
    private let repoID = 987_654
    private var doneKey: String { "checkboxDoneColumnID_\(repoID)" }
    private var ideaKey: String { "ideaColumnID_\(repoID)" }

    /// The container is dropped here, in a synchronous `tearDown`, as the other suites do.
    override func tearDown() {
        container = nil
        UserDefaults.standard.removeObject(forKey: doneKey)
        UserDefaults.standard.removeObject(forKey: ideaKey)
    }

    private func makeBoard() throws -> Board {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: ProjectRepo.self, TaskItem.self, KanbanColumn.self, GitHubAccount.self, configurations: config)
        self.container = container
        let context = container.mainContext
        let repo = ProjectRepo(repoID: repoID, name: "Roles")
        context.insert(repo)
        let todo = KanbanColumn(name: "To Do", orderIndex: 0, project: repo)
        let ideas = KanbanColumn(name: "Ideas", orderIndex: 1, project: repo)
        let done = KanbanColumn(name: "Done", orderIndex: 2, project: repo)
        [todo, ideas, done].forEach(context.insert)
        try context.save()
        return Board(context: context, repo: repo, todo: todo, ideas: ideas, done: done)
    }

    func testTheRolesAnswerWhatTheRepoAnswersTaskByTask() throws {
        let board = try makeBoard()
        UserDefaults.standard.set(board.ideas.id.uuidString, forKey: ideaKey)
        let tasks = [
            board.task("a", in: board.todo),
            board.task("b", in: board.ideas),
            board.task("c", in: board.done),
        ]
        try board.context.save()

        let roles = RepoColumnRoles(board.repo)

        XCTAssertEqual(roles.doneID, board.done.id, "the column named Done, as the repo finds it")
        XCTAssertEqual(roles.doneID, board.repo.doneColumn?.id)
        XCTAssertEqual(roles.ideaID, board.ideas.id)
        for item in tasks {
            XCTAssertEqual(roles.isIdea(item), board.repo.isIdea(item), item.content)
        }
        XCTAssertEqual(tasks.map(roles.isIdea), [false, true, false])
    }

    func testNoIdeaColumnChosenMeansNothingIsAnIdea() throws {
        let board = try makeBoard()
        let item = board.task("a", in: board.ideas)
        try board.context.save()

        let roles = RepoColumnRoles(board.repo)

        XCTAssertNil(roles.ideaID)
        XCTAssertFalse(roles.isIdea(item), "a column called Ideas is not the chosen ideas column")
    }

    func testTheChosenDoneColumnWinsOverTheNamedOne() throws {
        let board = try makeBoard()
        UserDefaults.standard.set(board.todo.id.uuidString, forKey: doneKey)

        XCTAssertEqual(RepoColumnRoles(board.repo).doneID, board.todo.id)
    }

    func testATaskWithoutAColumnIsNeverAnIdea() throws {
        let board = try makeBoard()
        UserDefaults.standard.set(board.ideas.id.uuidString, forKey: ideaKey)
        let orphan = board.task("lost", in: nil)

        XCTAssertFalse(RepoColumnRoles(board.repo).isIdea(orphan))
    }
}
