import SwiftData
import SwiftUI
import UIKit  // For UISelectionFeedbackGenerator

@MainActor
@Observable
final class KanbanViewModel {
    var project: ProjectRepo
    var modelContext: ModelContext

    // Voice Manager
    var voiceManager = VoiceManager()

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

    init(project: ProjectRepo, modelContext: ModelContext) {
        self.project = project
        self.modelContext = modelContext
    }

    // MARK: - Voice Actions

    func checkVoicePermissions() async {
        await voiceManager.checkAndRequestPermissions()
    }

    func createTaskFromVoice() {
        let text = voiceManager.transcribedText
        guard !text.isEmpty else { return }

        // Smart Routing: Check if voice manager detected a target column
        var targetColumn: KanbanColumn?

        if let detectedName = voiceManager.detectedColumnName {
            // Fuzzy/Exact match the column name
            targetColumn = (project.columns ?? []).first { col in
                col.name.localizedCaseInsensitiveContains(detectedName)
            }
        }

        // Default to first column if no smart route found
        if targetColumn == nil {
            targetColumn =
                (project.columns ?? []).sorted(by: { $0.orderIndex < $1.orderIndex }).first
        }

        if let targetColumn {
            createTask(content: text, column: targetColumn)
        }
    }

    // MARK: - Column Actions

    func initializeDefaultColumnsIfNeeded() {
        guard project.columns?.isEmpty ?? true else { return }

        // Default Columns strings
        let defaults = ["Brainstorming", "To-Do", "Done"]
        for (index, name) in defaults.enumerated() {
            let col = KanbanColumn(name: name, orderIndex: index, project: project)
            modelContext.insert(col)
        }
    }

    func createColumn() {
        guard !newColumnName.isEmpty else { return }
        let index = project.columns?.count ?? 0
        let col = KanbanColumn(name: newColumnName, orderIndex: index, project: project)
        withAnimation {
            modelContext.insert(col)
        }
        newColumnName = ""
    }

    func deleteColumn(_ column: KanbanColumn) {
        withAnimation {
            modelContext.delete(column)
        }
    }

    func startRenaming(_ column: KanbanColumn) {
        columnToRename = column
        renameColumnText = column.name
        showRenameColumnAlert = true
    }

    func renameColumn() {
        guard let col = columnToRename, !renameColumnText.isEmpty else { return }
        col.name = renameColumnText
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
        // Set status based on column name (simple logic for now)
        let status = column.name.lowercased().replacingOccurrences(of: " ", with: "_")
        let task = TaskItem(content: content, status: status, column: column, project: project)
        withAnimation {
            modelContext.insert(task)
        }
    }

    func deleteTask(_ task: TaskItem) {
        withAnimation {
            modelContext.delete(task)
        }
    }

    func moveTask(_ task: TaskItem, to column: KanbanColumn) {
        guard task.column != column else { return }
        withAnimation(.snappy) {
            task.column = column
            // Update status string to match new column
            task.status = column.name.lowercased().replacingOccurrences(of: " ", with: "_")
        }
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}
