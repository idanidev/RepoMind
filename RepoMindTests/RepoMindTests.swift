import SwiftData
import SwiftUI
import XCTest

@testable import RepoMind

// MARK: - Kanban Tests

@MainActor
final class KanbanTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var viewModel: KanbanViewModel!
    var project: ProjectRepo!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: ProjectRepo.self, TaskItem.self, KanbanColumn.self, GitHubAccount.self,
            configurations: config)
        modelContext = modelContainer.mainContext
        project = ProjectRepo(repoID: 1, name: "Test Project")
        modelContext.insert(project)
        viewModel = KanbanViewModel(project: project, modelContext: modelContext)
    }

    override func tearDown() {
        viewModel = nil
        project = nil
        modelContext = nil
        modelContainer = nil
    }

    func testInitializeDefaultColumns() {
        viewModel.initializeDefaultColumnsIfNeeded()
        XCTAssertEqual(project.columns?.count ?? 0, 3)
        let sorted = (project.columns ?? []).sorted { $0.orderIndex < $1.orderIndex }
        XCTAssertEqual(sorted.first?.name, "Brainstorming")
    }

    func testInitializeDefaultColumnsOnlyOnce() {
        viewModel.initializeDefaultColumnsIfNeeded()
        viewModel.initializeDefaultColumnsIfNeeded()
        XCTAssertEqual(project.columns?.count ?? 0, 3)
    }

    func testAddColumn() {
        viewModel.newColumnName = "Backlog"
        viewModel.createColumn()
        XCTAssertEqual(project.columns?.count ?? 0, 1)
        XCTAssertEqual(project.columns?.first?.name, "Backlog")
        XCTAssertEqual(viewModel.newColumnName, "")
    }

    func testAddColumnWithWhitespace() {
        viewModel.newColumnName = "  Backlog  "
        viewModel.createColumn()
        XCTAssertEqual(project.columns?.first?.name, "Backlog")
    }

    func testAddColumnEmpty() {
        viewModel.newColumnName = ""
        viewModel.createColumn()
        XCTAssertEqual(project.columns?.count ?? 0, 0)
    }

    func testCreateTask() {
        viewModel.initializeDefaultColumnsIfNeeded()
        let column = (project.columns ?? []).first(where: { $0.name == "To-Do" })!
        viewModel.createTask(content: "Test Task", column: column)
        XCTAssertEqual(column.tasks?.count, 1)
        XCTAssertEqual(column.tasks?.first?.content, "Test Task")
    }

    func testCreateTaskEmpty() {
        viewModel.initializeDefaultColumnsIfNeeded()
        let column = project.columns!.first!
        viewModel.createTask(content: "", column: column)
        XCTAssertEqual(column.tasks?.count ?? 0, 0)
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
    }

    func testDeleteTask() {
        viewModel.initializeDefaultColumnsIfNeeded()
        let column = project.columns!.first!
        viewModel.createTask(content: "To Delete", column: column)
        let task = column.tasks!.first!
        viewModel.deleteTask(task)
        XCTAssertEqual(column.tasks?.count, 0)
    }
}

// MARK: - Subscription Manager Tests

final class SubscriptionManagerTests: XCTestCase {
    func testCanAddAccountFree() {
        let manager = SubscriptionManager.shared
        XCTAssertTrue(manager.canAddAccount(currentCount: 0))
        XCTAssertFalse(manager.canAddAccount(currentCount: 1))
    }

    func testCanAddRepoFree() {
        let manager = SubscriptionManager.shared
        XCTAssertTrue(manager.canAddRepo(currentCount: 0, accountIsPro: false))
        XCTAssertFalse(manager.canAddRepo(currentCount: 3, accountIsPro: false))
    }

    func testCanAddRepoPro() {
        let manager = SubscriptionManager.shared
        XCTAssertTrue(manager.canAddRepo(currentCount: 1000, accountIsPro: true))
    }
}

// MARK: - Toast Manager Tests

@MainActor
final class ToastManagerTests: XCTestCase {
    func testShowToast() {
        let manager = ToastManager.shared
        manager.show("Test", style: .success)
        XCTAssertNotNil(manager.currentToast)
        XCTAssertEqual(manager.currentToast?.message, "Test")
    }

    func testToastStyles() {
        XCTAssertEqual(ToastStyle.error.iconName, "xmark.circle.fill")
        XCTAssertEqual(ToastStyle.success.tintColor, .green)
    }
}

// MARK: - Voice Manager Tests

@MainActor
final class VoiceManagerTests: XCTestCase {
    func testInitialState() {
        let vm = VoiceManager()
        XCTAssertFalse(vm.isRecording)
        XCTAssertEqual(vm.transcribedText, "")
        XCTAssertNil(vm.errorMessage)
    }

    func testCustomLocale() {
        let vm = VoiceManager(locale: Locale(identifier: "en-US"))
        XCTAssertEqual(vm.speechLocale.identifier, "en-US")
    }
}

// MARK: - GitHub Service Tests

final class GitHubServiceTests: XCTestCase {
    func testValidateTokenMockPro() async throws {
        let user = try await GitHubService.shared.validateToken("mock-pro")
        XCTAssertEqual(user.login, "ProDev")
    }

    func testFetchReposMockPro() async throws {
        let repos = try await GitHubService.shared.fetchRepos(token: "mock-pro")
        XCTAssertEqual(repos.count, 10)
    }

    func testFetchStarredIDs() async throws {
        let ids = try await GitHubService.shared.fetchStarredRepoIDs(token: "mock-pro")
        XCTAssertTrue(ids.contains(101))
    }
}

// MARK: - Keychain Manager Tests

final class KeychainManagerTests: XCTestCase {
    private let testKey = "test-key-\(UUID().uuidString)"

    override func tearDown() async throws {
        try? await KeychainManager.shared.deleteToken(for: testKey)
    }

    func testSaveAndRetrieve() async throws {
        try await KeychainManager.shared.saveToken("test123", for: testKey)
        let retrieved = try await KeychainManager.shared.retrieveToken(for: testKey)
        XCTAssertEqual(retrieved, "test123")
    }

    func testDelete() async throws {
        try await KeychainManager.shared.saveToken("delete_me", for: testKey)
        try await KeychainManager.shared.deleteToken(for: testKey)
        let result = try await KeychainManager.shared.retrieveToken(for: testKey)
        XCTAssertNil(result)
    }
}

// MARK: - Model Tests

@MainActor
final class ModelTests: XCTestCase {
    func testProjectRepoDefaults() {
        let repo = ProjectRepo(repoID: 1, name: "Test")
        XCTAssertEqual(repo.repoDescription, "")
        XCTAssertFalse(repo.isFavorite)
        XCTAssertFalse(repo.isArchived)
    }

    func testTaskItemDefaults() {
        let task = TaskItem(content: "Test")
        XCTAssertEqual(task.status, "todo")
        XCTAssertNil(task.audioPath)
    }
}
