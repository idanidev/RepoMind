import SwiftData
import SwiftUI
import UIKit

@MainActor
@Observable
final class KanbanViewModel {
    private(set) var project: ProjectRepo
    private let modelContext: ModelContext

    private(set) var voiceManager = VoiceManager()

    // Sheet States
    var editingTask: TaskItem?
    var showAddColumnSheet = false
    var newColumnName = ""
    var showAddTaskSheet = false
    var newTaskContent = ""
    var targetColumnForNewTask: KanbanColumn?

    // Rename Column State
    var showRenameColumnAlert = false
    var renameColumnText = ""
    var columnToRename: KanbanColumn?

    // Move Task State
    var showMoveSheet = false
    var taskToMove: TaskItem?

    // Drag State
    var draggingTask: TaskItem?

    // Columna actualmente visible (actualizada desde la vista)
    var currentColumn: KanbanColumn?

    // Feedback generators
    private static let selectionFeedback = UISelectionFeedbackGenerator()
    private static let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    init(project: ProjectRepo, modelContext: ModelContext) {
        self.project = project
        self.modelContext = modelContext
    }

    // MARK: - GitHub Issue Sync

    private var isDemoMode: Bool {
        UserDefaults.standard.bool(forKey: "isDemoMode")
    }

    private func resolveToken() async -> String? {
        guard let account = project.account else { return nil }
        return try? await KeychainManager.shared.retrieveToken(for: account.tokenKey)
    }

    /// The column that means "done", and therefore closes the linked GitHub issue.
    ///
    /// Deliberately the *same* column the checkbox moves tasks to. These used to be two separate
    /// notions — the checkbox used the configured column while issue sync used whichever column
    /// happened to sit last — so on a board where they differed, dragging a card closed a real
    /// GitHub issue the user never marked as done.
    private func isFinalColumn(_ column: KanbanColumn?) -> Bool {
        guard let column else { return false }
        return doneColumn(from: project.columns ?? [])?.id == column.id
    }

    /// Runs a GitHub sync operation without ever blocking or failing the local mutation.
    /// On success clears `needsIssueSync`; on permission/existence errors disables the toggle;
    /// on any other failure marks the task for retry via `reconcile`.
    /// One in-flight chain per task id, so operations on the same task stay ordered.
    private var syncChains: [UUID: Task<Void, Never>] = [:]

    private func runSync(_ task: TaskItem, _ operation: @escaping (String) async throws -> Void) {
        guard project.syncTasksToGitHub, !isDemoMode else { return }
        let repo = project
        let taskID = task.id
        let previous = syncChains[taskID]

        syncChains[taskID] = Task {
            // Serialise per task. Moving a card twice quickly fires close() then reopen() as
            // independent requests; when they raced, the slower one won and left the issue closed
            // while the task sat in another column — a state reconcile() never repairs.
            await previous?.value

            guard let token = await self.resolveToken() else {
                task.needsIssueSync = true
                try? self.modelContext.save()
                return
            }
            do {
                try await operation(token)
                task.needsIssueSync = false
            } catch TaskIssueSyncService.SyncError.noPermission, TaskIssueSyncService.SyncError.notFound {
                repo.syncTasksToGitHub = false
                repo.syncTasksDisabledReason = String(localized: "sync_tasks_disabled_no_permission")
            } catch {
                task.needsIssueSync = true
            }
            try? self.modelContext.save()
        }
    }

    /// Called once when the board appears — retries any tasks that failed a previous sync attempt.
    func reconcileGitHubSyncIfNeeded() async {
        guard project.syncTasksToGitHub, project.syncTasksDisabledReason == nil, !isDemoMode else { return }
        guard let token = await resolveToken() else { return }
        await TaskIssueSyncService.shared.reconcile(repo: project, context: modelContext, token: token)
    }

    /// Called by `TaskEditSheet` after content and/or column were edited.
    func handleTaskEdited(_ task: TaskItem, previousColumn: KanbanColumn?) {
        guard project.syncTasksToGitHub, !isDemoMode else { return }
        let newColumn = task.column
        let columnChanged = previousColumn?.id != newColumn?.id
        guard columnChanged else {
            runSync(task) { token in
                try await TaskIssueSyncService.shared.updateIssueContent(for: task, repo: self.project, token: token)
            }
            return
        }

        let wasFinal = isFinalColumn(previousColumn)
        let nowFinal = isFinalColumn(newColumn)
        runSync(task) { token in
            try await TaskIssueSyncService.shared.updateIssueContent(for: task, repo: self.project, token: token)
            if nowFinal {
                try await TaskIssueSyncService.shared.updateIssueColumn(for: task, repo: self.project, token: token)
                try await TaskIssueSyncService.shared.closeIssue(for: task, repo: self.project, reason: "completed", token: token)
            } else if wasFinal {
                try await TaskIssueSyncService.shared.reopenIssue(for: task, repo: self.project, token: token)
                try await TaskIssueSyncService.shared.updateIssueColumn(for: task, repo: self.project, token: token)
            } else {
                try await TaskIssueSyncService.shared.updateIssueColumn(for: task, repo: self.project, token: token)
            }
        }
    }

    // MARK: - Voice Actions

    func checkVoicePermissions() async {
        await voiceManager.checkAndRequestPermissions()
    }

    /// Updates the recognizer's vocabulary with column names and routing commands.
    /// Call this whenever columns change or before starting recording.
    func updateVoiceContextualStrings() {
        let columnNames = (project.columns ?? []).map(\.name)
        let commands = ["añadir a", "mover a", "add to", "move to"]
        voiceManager.contextualStrings = columnNames + commands
    }

    func createTaskFromVoice() {
        let text = voiceManager.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        var targetColumn: KanbanColumn?

        if let detectedName = voiceManager.detectedColumnName {
            targetColumn = (project.columns ?? []).first { col in
                col.name.localizedStandardContains(detectedName)
            }
        }

        if targetColumn == nil {
            // Usar la columna visible actualmente; si no, la primera
            targetColumn =
                currentColumn
                ?? (project.columns ?? [])
                .sorted { $0.orderIndex < $1.orderIndex }
                .first
        }

        if let targetColumn {
            createTask(content: text, column: targetColumn)
        }

        voiceManager.transcribedText = ""
    }

    // MARK: - Column Actions

    func initializeDefaultColumnsIfNeeded() {
        guard project.columns?.isEmpty ?? true else { return }

        let defaults = [
            String(localized: "default_column_1"),
            String(localized: "default_column_2"),
            String(localized: "default_column_3"),
        ]
        for (index, name) in defaults.enumerated() {
            let col = KanbanColumn(name: name, orderIndex: index, project: project)
            modelContext.insert(col)
        }

        try? modelContext.save()
    }

    @discardableResult
    func createColumn() -> Bool {
        let name = newColumnName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }

        let currentCount = project.columns?.count ?? 0
        guard SubscriptionManager.shared.canAddKanbanColumn(currentCount: currentCount) else {
            return false
        }

        let col = KanbanColumn(name: name, orderIndex: currentCount, project: project)

        withAnimation(.snappy) {
            modelContext.insert(col)
        }

        newColumnName = ""

        if project.syncTasksToGitHub, !isDemoMode {
            let repo = project
            Task {
                guard let token = await self.resolveToken() else { return }
                await TaskIssueSyncService.shared.ensureLabels(repo: repo, columns: [col], token: token)
            }
        }
        return true
    }

    func deleteColumn(_ column: KanbanColumn) {
        withAnimation(.snappy) {
            modelContext.delete(column)
        }
    }

    func startRenaming(_ column: KanbanColumn) {
        columnToRename = column
        renameColumnText = column.name
        showRenameColumnAlert = true
    }

    func renameColumn() {
        let name = renameColumnText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let col = columnToRename, !name.isEmpty else { return }

        col.name = name
        columnToRename = nil
        renameColumnText = ""

        // New slug for the renamed column — create its label, but existing issues keep their old label (v1 limitation).
        if project.syncTasksToGitHub, !isDemoMode {
            let repo = project
            Task {
                guard let token = await self.resolveToken() else { return }
                await TaskIssueSyncService.shared.ensureLabels(repo: repo, columns: [col], token: token)
            }
        }
    }

    // MARK: - Task Actions

    func prepareAddTask(for column: KanbanColumn) {
        targetColumnForNewTask = column
        newTaskContent = ""
        showAddTaskSheet = true
    }

    func createTask(content: String, column: KanbanColumn, imageData: Data? = nil) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        // Calcular el siguiente orderIndex
        let maxOrder = (column.tasks ?? []).map(\.orderIndex).max() ?? -1
        let newOrder = maxOrder + 1

        let status = column.name.lowercased().replacingOccurrences(of: " ", with: "_")
        let task = TaskItem(
            content: trimmedContent,
            status: status,
            column: column,
            project: project,
            orderIndex: newOrder
        )
        task.imageData = imageData

        withAnimation(.snappy) {
            modelContext.insert(task)
        }

        Self.impactFeedback.impactOccurred()

        runSync(task) { token in
            try await TaskIssueSyncService.shared.createIssue(for: task, repo: self.project, token: token)
        }
    }

    func deleteTask(_ task: TaskItem) {
        let issueNumber = task.issueNumber
        let repo = project
        let shouldSync = repo.syncTasksToGitHub && !isDemoMode

        withAnimation(.snappy) {
            modelContext.delete(task)
        }
        Self.impactFeedback.impactOccurred()

        if shouldSync, let issueNumber {
            Task {
                guard let token = await self.resolveToken() else { return }
                try? await TaskIssueSyncService.shared.deleteIssue(issueNumber: issueNumber, repo: repo, token: token)
            }
        }
    }

    func showMoveTaskSheet(_ task: TaskItem) {
        taskToMove = task
        showMoveSheet = true
    }

    // MARK: - Done Column (Checkbox)

    func moveTaskToDoneColumn(_ task: TaskItem) {
        guard let doneCol = doneColumn(from: project.columns ?? []) else {
            ToastManager.shared.show(String(localized: "no_done_column_configured"), style: .info)
            return
        }
        guard task.column?.id != doneCol.id else { return }
        moveTask(task, to: doneCol, atIndex: nil)
        Self.impactFeedback.impactOccurred()
    }

    func setDoneColumn(_ column: KanbanColumn?) {
        let key = "checkboxDoneColumnID_\(project.repoID)"
        if let column {
            UserDefaults.standard.set(column.id.uuidString, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Delegates to the model so there is exactly one definition of "done" — the split between
    /// this and the issue-sync notion of a final column is what let a drag close a real issue.
    func doneColumn(from columns: [KanbanColumn]) -> KanbanColumn? {
        project.doneColumn(from: columns)
    }

    func moveTask(_ task: TaskItem, to column: KanbanColumn, atIndex index: Int?) {
        let isSameColumn = task.column?.id == column.id
        let previousColumn = task.column
        let wasFinal = isFinalColumn(previousColumn)

        withAnimation(.snappy) {
            // Si se mueve a otra columna
            if !isSameColumn {
                task.column = column
                task.status = column.name.lowercased().replacingOccurrences(of: " ", with: "_")
            }

            // Reordenar dentro de la columna
            if let targetIndex = index {
                reorderTask(task, inColumn: column, toIndex: targetIndex)
            } else if !isSameColumn {
                // Si es nueva columna sin índice específico, poner al final
                let maxOrder = (column.tasks ?? []).filter { $0.id != task.id }.map(\.orderIndex).max() ?? -1
                task.orderIndex = maxOrder + 1
            }
        }

        Self.selectionFeedback.selectionChanged()

        if !isSameColumn {
            let nowFinal = isFinalColumn(column)
            runSync(task) { token in
                if nowFinal {
                    try await TaskIssueSyncService.shared.updateIssueColumn(for: task, repo: self.project, token: token)
                    try await TaskIssueSyncService.shared.closeIssue(for: task, repo: self.project, reason: "completed", token: token)
                } else if wasFinal {
                    try await TaskIssueSyncService.shared.reopenIssue(for: task, repo: self.project, token: token)
                    try await TaskIssueSyncService.shared.updateIssueColumn(for: task, repo: self.project, token: token)
                } else {
                    try await TaskIssueSyncService.shared.updateIssueColumn(for: task, repo: self.project, token: token)
                }
            }
        }
    }

    private func reorderTask(_ task: TaskItem, inColumn column: KanbanColumn, toIndex targetIndex: Int) {
        var tasks = (column.tasks ?? []).sorted { $0.orderIndex < $1.orderIndex }

        // Remover la tarea de su posición actual si está en la misma columna
        if let currentIndex = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks.remove(at: currentIndex)
        }

        // Insertar en la nueva posición
        let insertIndex = min(targetIndex, tasks.count)
        tasks.insert(task, at: insertIndex)

        // Actualizar todos los orderIndex
        for (index, t) in tasks.enumerated() {
            t.orderIndex = index
        }
    }
}
