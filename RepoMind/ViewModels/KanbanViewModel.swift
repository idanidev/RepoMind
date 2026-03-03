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

    // MARK: - Voice Actions

    func checkVoicePermissions() async {
        await voiceManager.checkAndRequestPermissions()
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
    }

    func deleteTask(_ task: TaskItem) {
        withAnimation(.snappy) {
            modelContext.delete(task)
        }
        Self.impactFeedback.impactOccurred()
    }

    func showMoveTaskSheet(_ task: TaskItem) {
        taskToMove = task
        showMoveSheet = true
    }

    func moveTask(_ task: TaskItem, to column: KanbanColumn, atIndex index: Int?) {
        let isSameColumn = task.column?.id == column.id

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
