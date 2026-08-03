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
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        modelContainer = try ModelContainer(
            for: ProjectRepo.self, TaskItem.self, KanbanColumn.self, GitHubAccount.self,
            configurations: config)
        modelContext = modelContainer.mainContext
        project = ProjectRepo(repoID: 1, name: "Test Project")
        modelContext.insert(project)
        viewModel = KanbanViewModel(project: project, modelContext: modelContext)
        // Enable Pro to avoid column limits in Kanban tests
        SubscriptionManager.shared.isMockPro = true
    }

    override func tearDown() {
        SubscriptionManager.shared.isMockPro = false
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

    /// Default columns are created from localized names, so selecting them by an English literal
    /// crashed on any machine not running in English. Order is the stable identity.
    private func sortedColumns() -> [KanbanColumn] {
        (project.columns ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    func testCreateTask() {
        viewModel.initializeDefaultColumnsIfNeeded()
        let column = sortedColumns()[1]
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
        let columns = sortedColumns()
        let todoCol = columns[1]
        let doneCol = columns[2]
        viewModel.createTask(content: "Moving Task", column: todoCol)
        let task = todoCol.tasks!.first!
        viewModel.moveTask(task, to: doneCol, atIndex: nil)
        XCTAssertEqual(todoCol.tasks?.count, 0)
        XCTAssertEqual(doneCol.tasks?.count, 1)
    }

    func testDeleteTask() {
        viewModel.initializeDefaultColumnsIfNeeded()
        let column = project.columns!.first!
        viewModel.createTask(content: "To Delete", column: column)
        let task = column.tasks!.first!
        viewModel.deleteTask(task)
        // The cached inverse relationship still holds the object until pending changes are
        // flushed. The app reads tasks through @Query, so its UI updates either way — the test
        // has to ask for the flush explicitly.
        modelContext.processPendingChanges()
        XCTAssertEqual(column.tasks?.count, 0)
    }
}

// MARK: - Subscription Manager Tests

@MainActor
final class SubscriptionManagerTests: XCTestCase {
    override func tearDown() {
        SubscriptionManager.shared.isMockPro = false
    }

    func testFreeUserCannotAddMultipleAccounts() {
        let manager = SubscriptionManager.shared
        manager.isMockPro = false
        XCTAssertTrue(manager.canAddAccount(currentCount: 0))
        XCTAssertFalse(manager.canAddAccount(currentCount: 1))
    }

    func testProUserCanAddUnlimitedAccounts() {
        let manager = SubscriptionManager.shared
        manager.isMockPro = true
        XCTAssertTrue(manager.canAddAccount(currentCount: 100))
    }

    func testCanAddRepoFree() {
        let manager = SubscriptionManager.shared
        manager.isMockPro = false
        XCTAssertTrue(manager.canAddRepo(currentCount: 0, accountIsPro: false))
        XCTAssertFalse(manager.canAddRepo(currentCount: 3, accountIsPro: false))
    }

    func testCanAddRepoPro() {
        let manager = SubscriptionManager.shared
        manager.isMockPro = true
        XCTAssertTrue(manager.canAddRepo(currentCount: 1000))
    }

    func testFreeKanbanColumnLimit() {
        let manager = SubscriptionManager.shared
        manager.isMockPro = false
        XCTAssertTrue(manager.canAddKanbanColumn(currentCount: 0))
        XCTAssertTrue(manager.canAddKanbanColumn(currentCount: 2))
        XCTAssertFalse(manager.canAddKanbanColumn(currentCount: 3))
    }

    func testProBypassesAllLimits() {
        let manager = SubscriptionManager.shared
        manager.isMockPro = true
        XCTAssertTrue(manager.canAddRepo(currentCount: 1000))
        XCTAssertTrue(manager.canAddKanbanColumn(currentCount: 100))
        XCTAssertTrue(manager.canAddAccount(currentCount: 50))
    }

    /// Previously had no assertions at all, so it passed unconditionally.
    /// Asserts the gating logic rather than `isPro` itself, which can be seeded from the Keychain
    /// cache in a test environment and is therefore not deterministic here.
    func testFreeTierLimitsApplyWhenNotPro() {
        let manager = SubscriptionManager.shared
        manager.isMockPro = false
        defer { manager.isMockPro = false }

        XCTAssertTrue(manager.canAddRepo(currentCount: manager.maxFreeRepos - 1))
        XCTAssertFalse(manager.canAddRepo(currentCount: manager.maxFreeRepos))
        XCTAssertFalse(manager.canAddAccount(currentCount: manager.maxFreeAccounts))
        XCTAssertFalse(manager.canAddKanbanColumn(currentCount: manager.maxFreeKanbanColumns))

        manager.isMockPro = true
        XCTAssertTrue(manager.canAddRepo(currentCount: 999))
        XCTAssertTrue(manager.canAddAccount(currentCount: 999))
        XCTAssertTrue(manager.canAddKanbanColumn(currentCount: 999))
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
    private var vm: VoiceManager?

    override func tearDown() {
        // Explicitly stop & nil to ensure clean deallocation
        vm?.stopRecording()
        vm = nil
    }

    func testInitialState() {
        vm = VoiceManager()
        XCTAssertFalse(vm!.isRecording)
        XCTAssertEqual(vm!.transcribedText, "")
        XCTAssertNil(vm!.errorMessage)
    }

    /// Replaces a test that passed a locale into an initialiser which ignored it, then asserted
    /// the value came back — it only ever passed on English machines, by coincidence.
    func testResolvesSpeechLocaleFromSystemPreferences() {
        vm = VoiceManager()
        let expected = Locale.preferredLanguages.first.flatMap {
            Locale(identifier: $0).language.languageCode?.identifier
        }
        XCTAssertEqual(vm!.speechLocale.language.languageCode?.identifier, expected)
        // Dual mode is only on when a second, different language is configured.
        XCTAssertEqual(vm!.useDualLanguage, vm!.secondaryLocale != nil)
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

// MARK: - Multi-Account Isolation Tests

@MainActor
final class MultiAccountIsolationTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        modelContainer = try ModelContainer(
            for: ProjectRepo.self, TaskItem.self, KanbanColumn.self, GitHubAccount.self,
            configurations: config)
        modelContext = modelContainer.mainContext
        SubscriptionManager.shared.isMockPro = true
    }

    override func tearDown() {
        SubscriptionManager.shared.isMockPro = false
        modelContext = nil
        modelContainer = nil
    }

    // MARK: - Test: Repos belong to correct account

    func testReposBelongToCorrectAccount() throws {
        // Crear dos cuentas
        let account1 = GitHubAccount(username: "user1", tokenKey: "token1")
        let account2 = GitHubAccount(username: "user2", tokenKey: "token2")
        modelContext.insert(account1)
        modelContext.insert(account2)

        // Crear repos para cada cuenta
        let repo1 = ProjectRepo(repoID: 100, name: "Repo-User1", account: account1)
        let repo2 = ProjectRepo(repoID: 200, name: "Repo-User2", account: account2)
        modelContext.insert(repo1)
        modelContext.insert(repo2)

        try modelContext.save()

        // Verificar que cada repo pertenece a su cuenta
        XCTAssertEqual(repo1.account?.username, "user1")
        XCTAssertEqual(repo2.account?.username, "user2")

        // Verificar que las cuentas tienen los repos correctos
        XCTAssertEqual(account1.repos?.count, 1)
        XCTAssertEqual(account2.repos?.count, 1)
        XCTAssertEqual(account1.repos?.first?.name, "Repo-User1")
        XCTAssertEqual(account2.repos?.first?.name, "Repo-User2")
    }

    // MARK: - Test: Tasks don't leak between accounts

    func testTasksDontLeakBetweenAccounts() throws {
        // Crear dos cuentas con repos
        let account1 = GitHubAccount(username: "alice", tokenKey: "token-alice")
        let account2 = GitHubAccount(username: "bob", tokenKey: "token-bob")
        modelContext.insert(account1)
        modelContext.insert(account2)

        let repoAlice = ProjectRepo(repoID: 1, name: "AliceRepo", account: account1)
        let repoBob = ProjectRepo(repoID: 2, name: "BobRepo", account: account2)
        modelContext.insert(repoAlice)
        modelContext.insert(repoBob)

        // Crear columnas para cada repo
        let colAlice = KanbanColumn(name: "Alice-ToDo", orderIndex: 0, project: repoAlice)
        let colBob = KanbanColumn(name: "Bob-ToDo", orderIndex: 0, project: repoBob)
        modelContext.insert(colAlice)
        modelContext.insert(colBob)

        // Crear tareas para cada columna
        let taskAlice = TaskItem(content: "Alice's secret task", column: colAlice, project: repoAlice)
        let taskBob = TaskItem(content: "Bob's private task", column: colBob, project: repoBob)
        modelContext.insert(taskAlice)
        modelContext.insert(taskBob)

        try modelContext.save()

        // Verificar aislamiento de columnas
        XCTAssertEqual(repoAlice.columns?.count, 1)
        XCTAssertEqual(repoBob.columns?.count, 1)
        XCTAssertEqual(repoAlice.columns?.first?.name, "Alice-ToDo")
        XCTAssertEqual(repoBob.columns?.first?.name, "Bob-ToDo")

        // Verificar aislamiento de tareas
        XCTAssertEqual(colAlice.tasks?.count, 1)
        XCTAssertEqual(colBob.tasks?.count, 1)
        XCTAssertEqual(colAlice.tasks?.first?.content, "Alice's secret task")
        XCTAssertEqual(colBob.tasks?.first?.content, "Bob's private task")

        // Verificar que Bob no puede ver tareas de Alice
        let bobTasks = repoBob.columns?.flatMap { $0.tasks ?? [] } ?? []
        XCTAssertFalse(bobTasks.contains(where: { $0.content.contains("Alice") }))

        // Verificar que Alice no puede ver tareas de Bob
        let aliceTasks = repoAlice.columns?.flatMap { $0.tasks ?? [] } ?? []
        XCTAssertFalse(aliceTasks.contains(where: { $0.content.contains("Bob") }))
    }

    // MARK: - Test: Deleting account cascades correctly

    func testDeletingAccountCascadesCorrectly() throws {
        // Crear cuenta con datos completos
        let account = GitHubAccount(username: "toDelete", tokenKey: "token-delete")
        modelContext.insert(account)

        let repo = ProjectRepo(repoID: 999, name: "DeleteMe", account: account)
        modelContext.insert(repo)

        let column = KanbanColumn(name: "Column", orderIndex: 0, project: repo)
        modelContext.insert(column)

        let task = TaskItem(content: "Task to delete", column: column, project: repo)
        modelContext.insert(task)

        try modelContext.save()

        // Guardar IDs para verificar después
        let repoID = repo.repoID
        let taskContent = task.content

        // Eliminar la cuenta
        modelContext.delete(account)
        try modelContext.save()

        // `GitHubAccount.repos` is `.nullify`, NOT `.cascade`, so the repo survives with a nil
        // account. This test used to assert cascade and failed; the model was never going to
        // behave that way.
        let repoFetch = FetchDescriptor<ProjectRepo>(predicate: #Predicate { $0.repoID == repoID })
        let remainingRepos = try modelContext.fetch(repoFetch)
        XCTAssertEqual(remainingRepos.count, 1, "Deleting an account nullifies the link, it does not cascade")
        XCTAssertNil(remainingRepos.first?.account, "The surviving repo is orphaned")

        let taskFetch = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.content == taskContent })
        let remainingTasks = try modelContext.fetch(taskFetch)
        XCTAssertEqual(remainingTasks.count, 1, "Tasks belong to the repo, which still exists")

        // This is exactly why sign-out has to delete repos itself: an orphaned repo has no
        // account, so the per-account filter never excludes it and it stayed visible under
        // "All accounts" to whoever signed in next.
    }

    // MARK: - Test: Same repo ID in different accounts stays separate

    func testSameRepoIDInDifferentAccountsStaysSeparate() throws {
        // Escenario: Usuario tiene el mismo fork en cuenta personal y de trabajo
        let personalAccount = GitHubAccount(username: "john-personal", tokenKey: "token1")
        let workAccount = GitHubAccount(username: "john-work", tokenKey: "token2")
        modelContext.insert(personalAccount)
        modelContext.insert(workAccount)

        // Mismo proyecto forkeado (diferentes repoIDs en GitHub, pero mismo nombre)
        let personalRepo = ProjectRepo(repoID: 1001, name: "awesome-project", account: personalAccount)
        let workRepo = ProjectRepo(repoID: 2001, name: "awesome-project", account: workAccount)
        modelContext.insert(personalRepo)
        modelContext.insert(workRepo)

        // Diferentes configuraciones para cada uno
        personalRepo.isFavorite = true
        workRepo.isFavorite = false
        personalRepo.logoURL = "https://personal-logo.png"
        workRepo.logoURL = "https://work-logo.png"

        try modelContext.save()

        // Verificar que son repos separados con config separada
        XCTAssertTrue(personalRepo.isFavorite)
        XCTAssertFalse(workRepo.isFavorite)
        XCTAssertEqual(personalRepo.logoURL, "https://personal-logo.png")
        XCTAssertEqual(workRepo.logoURL, "https://work-logo.png")
        XCTAssertNotEqual(personalRepo.account?.id, workRepo.account?.id)
    }

    // MARK: - Test: Filtering repos by account works correctly

    func testFilteringReposByAccount() throws {
        let account1 = GitHubAccount(username: "dev1", tokenKey: "t1")
        let account2 = GitHubAccount(username: "dev2", tokenKey: "t2")
        modelContext.insert(account1)
        modelContext.insert(account2)

        // Crear 3 repos para account1 y 2 para account2
        for i in 1...3 {
            let repo = ProjectRepo(repoID: i, name: "Repo-Dev1-\(i)", account: account1)
            modelContext.insert(repo)
        }
        for i in 4...5 {
            let repo = ProjectRepo(repoID: i, name: "Repo-Dev2-\(i)", account: account2)
            modelContext.insert(repo)
        }

        try modelContext.save()

        // Simular filtrado como lo hace ContentView
        let allReposFetch = FetchDescriptor<ProjectRepo>()
        let allRepos = try modelContext.fetch(allReposFetch)

        let account1Repos = allRepos.filter { $0.account?.id == account1.id }
        let account2Repos = allRepos.filter { $0.account?.id == account2.id }

        XCTAssertEqual(account1Repos.count, 3)
        XCTAssertEqual(account2Repos.count, 2)
        XCTAssertTrue(account1Repos.allSatisfy { $0.name.contains("Dev1") })
        XCTAssertTrue(account2Repos.allSatisfy { $0.name.contains("Dev2") })
    }
}

// MARK: - Repo Identity

@MainActor
final class RepoFullNameTests: XCTestCase {
    func testDerivesOwnerFromHTMLURL() {
        let repo = ProjectRepo(repoID: 1, name: "RepoMind", htmlURL: "https://github.com/idanidev/RepoMind")
        XCTAssertEqual(repo.fullName, "idanidev/RepoMind")
    }

    /// The bug this guards: the copy of this parsing behind the unread badge omitted the
    /// fallback, produced "/RepoMind", matched nothing, and the badge always read zero.
    func testFallsBackToBareNameWhenURLMissing() {
        XCTAssertEqual(ProjectRepo(repoID: 1, name: "RepoMind", htmlURL: "").fullName, "RepoMind")
        XCTAssertEqual(ProjectRepo(repoID: 2, name: "Local", htmlURL: "not a url").fullName, "Local")
    }
}

// MARK: - Task ↔ Issue Sync

@MainActor
final class TaskIssueSyncLabelTests: XCTestCase {
    private func label(_ name: String) -> String {
        TaskIssueSyncService.columnLabel(for: KanbanColumn(name: name, orderIndex: 0))
    }

    func testSlugIsLowercasedAndHyphenated() {
        XCTAssertEqual(label("In Progress"), "col:in-progress")
    }

    func testStripsDiacritics() {
        XCTAssertEqual(label("En progreso"), "col:en-progreso")
        XCTAssertEqual(label("Hecho"), "col:hecho")
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertEqual(label("  Pendiente  "), "col:pendiente")
    }
}

// MARK: - Feedback Severity

@MainActor
final class FeedbackSeverityTests: XCTestCase {
    func testMapsLabelsToSeverity() {
        XCTAssertEqual(FeedbackSeverity.from(labels: ["user-feedback", "bug:critical"]), .critical)
        XCTAssertEqual(FeedbackSeverity.from(labels: ["user-feedback", "bug:minor"]), .minor)
        XCTAssertEqual(FeedbackSeverity.from(labels: ["user-feedback", "enhancement"]), .enhancement)
        XCTAssertEqual(FeedbackSeverity.from(labels: ["user-feedback"]), .general)
    }

    func testCriticalWinsOverOtherLabels() {
        XCTAssertEqual(
            FeedbackSeverity.from(labels: ["enhancement", "bug:minor", "bug:critical"]), .critical)
    }

    func testIsCaseInsensitive() {
        XCTAssertEqual(FeedbackSeverity.from(labels: ["Bug:Critical"]), .critical)
    }
}

// MARK: - Deep Links

@MainActor
final class DeepLinkHandlerTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(
            for: ProjectRepo.self, TaskItem.self, KanbanColumn.self, GitHubAccount.self,
            configurations: config)
        context = container.mainContext
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    @discardableResult
    private func makeRepo(_ name: String) -> ProjectRepo {
        let repo = ProjectRepo(repoID: abs(name.hashValue), name: name)
        context.insert(repo)
        let column = KanbanColumn(name: "Pendiente", orderIndex: 0, project: repo)
        context.insert(column)
        return repo
    }

    private func tasks(in repo: ProjectRepo) -> [TaskItem] { repo.tasks ?? [] }

    func testCreatesTaskInNamedRepo() {
        let target = makeRepo("RepoMind")
        makeRepo("Clarity")

        DeepLinkHandler.handle(URL(string: "repomind://add-task?content=Hola&repo=RepoMind")!, in: context)

        XCTAssertEqual(tasks(in: target).count, 1)
        XCTAssertEqual(tasks(in: target).first?.content, "Hola")
    }

    /// A substring match sent `repo=api` to "api-legacy", filing the task against the wrong repo.
    func testPrefersExactRepoMatchOverSubstring() {
        let exact = makeRepo("api")
        let similar = makeRepo("api-legacy")

        DeepLinkHandler.handle(URL(string: "repomind://add-task?content=Test&repo=api")!, in: context)

        XCTAssertEqual(tasks(in: exact).count, 1)
        XCTAssertEqual(tasks(in: similar).count, 0)
    }

    func testIgnoresLinkWithoutContent() {
        let repo = makeRepo("RepoMind")
        DeepLinkHandler.handle(URL(string: "repomind://add-task?repo=RepoMind")!, in: context)
        XCTAssertEqual(tasks(in: repo).count, 0)
    }

    func testIgnoresForeignScheme() {
        let repo = makeRepo("RepoMind")
        DeepLinkHandler.handle(URL(string: "otherapp://add-task?content=Nope&repo=RepoMind")!, in: context)
        XCTAssertEqual(tasks(in: repo).count, 0)
    }

    func testAppendsToTheEndOfTheColumn() {
        let repo = makeRepo("RepoMind")
        for i in 1...3 {
            DeepLinkHandler.handle(
                URL(string: "repomind://add-task?content=Task\(i)&repo=RepoMind")!, in: context)
        }
        let ordered = tasks(in: repo).sorted { $0.orderIndex < $1.orderIndex }
        XCTAssertEqual(ordered.map(\.content), ["Task1", "Task2", "Task3"])
        XCTAssertEqual(ordered.map(\.orderIndex), [0, 1, 2])
    }
}
