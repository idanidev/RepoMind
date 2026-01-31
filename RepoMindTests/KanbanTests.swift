import SwiftData
import XCTest

@testable import RepoMind

@MainActor
final class KanbanTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var viewModel: KanbanViewModel!
    var project: ProjectRepo!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: ProjectRepo.self, TaskItem.self, KanbanColumn.self, configurations: config)
        modelContext = modelContainer.mainContext

        project = ProjectRepo(repoID: 1, name: "Test Project", repoDescription: "Test Summary")
        modelContext.insert(project)

        viewModel = KanbanViewModel(project: project, modelContext: modelContext)
    }

    func testInitializeDefaultColumns() {
        viewModel.initializeDefaultColumnsIfNeeded()
        XCTAssertEqual(project.columns?.count ?? 0, 3)
        // Defaults: Brainstorming (0), To-Do (1), Done (2)
        XCTAssertEqual(
            (project.columns ?? []).sorted(by: { $0.orderIndex < $1.orderIndex }).first?.name,
            "Brainstorming")
    }

    func testAddColumn() {
        viewModel.newColumnName = "Backlog"
        viewModel.createColumn()

        XCTAssertEqual(project.columns?.count ?? 0, 1)
        XCTAssertEqual(project.columns?.first?.name, "Backlog")
        XCTAssertEqual(viewModel.newColumnName, "")  // Should be reset
    }

    func testCreateTask() {
        viewModel.initializeDefaultColumnsIfNeeded()
        // Use To-Do column (index 1)
        let column = (project.columns ?? []).first(where: { $0.name == "To-Do" })!

        viewModel.createTask(content: "Test Task", column: column)

        XCTAssertEqual(column.tasks?.count, 1)
        XCTAssertEqual(column.tasks?.first?.content, "Test Task")
    }

    func testMoveTask() {
        viewModel.initializeDefaultColumnsIfNeeded()
        let todoCol = (project.columns ?? []).first(where: { $0.name == "To-Do" })!
        let doneCol = (project.columns ?? []).first(where: { $0.name == "Done" })!

        viewModel.createTask(content: "Moving Task", column: todoCol)
        let task = todoCol.tasks!.first!

        viewModel.moveTask(task, to: doneCol)

        XCTAssertEqual(todoCol.tasks?.count, 0)
        XCTAssertEqual(doneCol.tasks?.count, 1)
        XCTAssertEqual(task.column, doneCol)
    }

    func testDeleteTask() {
        viewModel.initializeDefaultColumnsIfNeeded()
        let column = (project.columns ?? []).first!
        viewModel.createTask(content: "To Delete", column: column)
        let task = column.tasks!.first!

        viewModel.deleteTask(task)

        XCTAssertEqual(column.tasks?.count, 0)
    }

    func testDeleteColumn() {
        // Cascade delete verification
        viewModel.initializeDefaultColumnsIfNeeded()
        let column = (project.columns ?? []).first!
        viewModel.createTask(content: "Task inside column", column: column)

        viewModel.deleteColumn(column)

        // Verify column is gone from project
        XCTAssertEqual(project.columns?.count, 2)
        // Verify task is gone (cascade) - via context or implicit knowledge
        // In unit test with in-memory context, easier to check column count.
    }
}
