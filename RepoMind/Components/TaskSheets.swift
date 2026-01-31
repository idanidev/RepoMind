import SwiftData
import SwiftUI

// MARK: - Task Edit Sheet

struct TaskEditSheet: View {
    @Bindable var task: TaskItem
    var columns: [KanbanColumn]
    @Environment(\.dismiss) private var dismiss

    @State private var editedContent: String = ""
    @State private var selectedColumn: KanbanColumn?

    var body: some View {
        NavigationStack {
            Form {
                Section("content") {
                    TextField("description_placeholder", text: $editedContent, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("column") {
                    Picker("column", selection: $selectedColumn) {
                        ForEach(columns) { column in
                            Text(column.name).tag(column as KanbanColumn?)
                        }
                    }
                }
            }
            .navigationTitle("edit_task_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") {
                        task.content = editedContent
                        task.column = selectedColumn
                        dismiss()
                    }
                    .disabled(editedContent.isEmpty)
                }
            }
            .onAppear {
                editedContent = task.content
                selectedColumn = task.column
            }
        }
    }
}

// MARK: - Add Task Sheet

struct AddTaskSheet: View {
    @Binding var content: String
    var columns: [KanbanColumn]
    var preselectedColumn: KanbanColumn?

    let onSave: (String, KanbanColumn) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedColumn: KanbanColumn?

    var body: some View {
        NavigationStack {
            Form {
                Section("task_section") {
                    TextField("task_placeholder", text: $content, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section("column") {
                    Picker("column", selection: $selectedColumn) {
                        ForEach(columns) { column in
                            Text(column.name).tag(column as KanbanColumn?)
                        }
                    }
                }
            }
            .navigationTitle("new_task_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("create") {
                        if let col = selectedColumn {
                            onSave(content, col)
                            dismiss()
                        }
                    }
                    .disabled(content.isEmpty || selectedColumn == nil)
                }
            }
            .onAppear {
                if let preselectedColumn {
                    selectedColumn = preselectedColumn
                } else {
                    selectedColumn = columns.first
                }
            }
        }
    }
}
