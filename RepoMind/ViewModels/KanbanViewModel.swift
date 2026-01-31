import SwiftData
import SwiftUI
import UIKit

@MainActor
@Observable
final class KanbanViewModel {
    // ✅ FIX: private(set) for properties that shouldn't be reassigned externally
    private(set) var project: ProjectRepo
    private let modelContext: ModelContext

    // ✅ FIX: private(set) for voiceManager
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

    // Drag State
    var draggingTask: TaskItem?

    // ✅ FIX: Static feedback generator for performance
    private static let selectionFeedback = UISelectionFeedbackGenerator()

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
            targetColumn =
                (project.columns ?? [])
                .sorted { $0.orderIndex < $1.orderIndex }
                .first
        }

        if let targetColumn {
            createTask(content: text, column: targetColumn)
        }

        // Reset voice state
        voiceManager.transcribedText = ""
    }

    // MARK: - Column Actions

    func initializeDefaultColumnsIfNeeded() {
        guard project.columns?.isEmpty ?? true else { return }

        let defaults = ["Brainstorming", "To-Do", "Done"]
        for (index, name) in defaults.enumerated() {
            let col = KanbanColumn(name: name, orderIndex: index, project: project)
            modelContext.insert(col)
        }

        // Save immediately to ensure columns are available
        try? modelContext.save()
    }

    func createColumn() {
        // ✅ FIX: Trim whitespace in validation
        let name = newColumnName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let index = project.columns?.count ?? 0
        let col = KanbanColumn(name: name, orderIndex: index, project: project)

        withAnimation(.snappy) {
            modelContext.insert(col)
        }

        newColumnName = ""
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
        // ✅ FIX: Trim whitespace in validation
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

    func createTask(content: String, column: KanbanColumn) {
        // ✅ FIX: Trim and validate content
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return }

        let status = column.name.lowercased().replacingOccurrences(of: " ", with: "_")
        let task = TaskItem(
            content: trimmedContent,
            status: status,
            column: column,
            project: project
        )

        withAnimation(.snappy) {
            modelContext.insert(task)
        }
    }

    func deleteTask(_ task: TaskItem) {
        withAnimation(.snappy) {
            modelContext.delete(task)
        }
    }

    func moveTask(_ task: TaskItem, to column: KanbanColumn) {
        guard task.column != column else { return }

        withAnimation(.snappy) {
            task.column = column
            task.status = column.name.lowercased().replacingOccurrences(of: " ", with: "_")
        }

        // ✅ FIX: Use static generator
        Self.selectionFeedback.selectionChanged()
    }
}
