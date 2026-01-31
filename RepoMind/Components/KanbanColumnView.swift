import SwiftData
import SwiftUI

struct KanbanColumnView: View {
    @Bindable var column: KanbanColumn
    @Binding var draggedTask: TaskItem?

    let onDropTask: (TaskItem) -> Void
    let onAdd: () -> Void
    let onEditTask: (TaskItem) -> Void
    let onDeleteTask: (TaskItem) -> Void
    let onDeleteColumn: () -> Void
    let onRenameColumn: () -> Void

    @State private var isTargeted = false
    // ✅ FIX: Cached sorted tasks
    @State private var sortedTasks: [TaskItem] = []

    var body: some View {
        GlassEffectContainer(cornerRadius: 12) {
            VStack(spacing: 0) {
                columnHeader

                if !column.isCollapsed {
                    columnContent
                    addTaskButton
                }
            }
        }
        .shadow(color: .black.opacity(isTargeted ? 0.15 : 0.05), radius: 8, y: 4)
        .task {
            updateSortedTasks()
        }
        // ✅ FIX: Use tasks count as proxy (relationships don't trigger onChange reliably)
        .onChange(of: column.tasks?.count) { _, _ in
            updateSortedTasks()
        }
    }

    // ✅ FIX: Cache sorted tasks
    private func updateSortedTasks() {
        sortedTasks = (column.tasks ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Header

    private var columnHeader: some View {
        HStack {
            collapseButton

            Text(column.name)
                .font(.headline)

            Spacer()

            if !column.isCollapsed {
                taskCountBadge
            }

            columnMenu
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items: items)
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.2)) {
                isTargeted = targeted
            }
        }
    }

    private var collapseButton: some View {
        Button {
            withAnimation(.snappy) {
                column.isCollapsed.toggle()
            }
        } label: {
            Label(
                column.isCollapsed ? "Expandir columna" : "Colapsar columna",
                systemImage: column.isCollapsed ? "chevron.right" : "chevron.down"
            )
            .labelStyle(.iconOnly)
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(column.isCollapsed ? "Expandir columna" : "Colapsar columna")
    }

    private var taskCountBadge: some View {
        Text("\(column.tasks?.count ?? 0)")
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .accessibilityLabel("\(column.tasks?.count ?? 0) tareas")
    }

    private var columnMenu: some View {
        Menu {
            Button(action: onRenameColumn) {
                Label("rename_column", systemImage: "pencil")
            }

            Button(role: .destructive, action: onDeleteColumn) {
                Label("delete_column", systemImage: "trash")
            }
        } label: {
            Label("Opciones de columna", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .padding(8)
        }
        .accessibilityLabel("Opciones de columna")
    }

    // MARK: - Content

    private var columnContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if sortedTasks.isEmpty {
                    emptyColumnState
                } else {
                    tasksContent
                }
            }
            .padding()
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items: items)
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.2)) {
                isTargeted = targeted
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted ? Color.accentColor.opacity(0.05) : .clear)
        )
    }

    // ✅ FIX: Separate empty state view
    private var emptyColumnState: some View {
        ContentUnavailableView {
            Label("column_empty", systemImage: "tray")
        } description: {
            Text("drag_tasks_here")
        }
        .frame(height: 150)
        .opacity(0.5)
    }

    // ✅ FIX: Separate tasks content view
    private var tasksContent: some View {
        ForEach(sortedTasks) { task in
            TaskCard(task: task)
                .contentShape(.dragPreview, RoundedRectangle(cornerRadius: 14))
                .draggable(task.id.uuidString) {
                    TaskCard(task: task)
                        .frame(width: 280)
                        .onAppear { draggedTask = task }
                }
                .contextMenu {
                    Button {
                        onEditTask(task)
                    } label: {
                        Label("edit_task", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        onDeleteTask(task)
                    } label: {
                        Label("delete_task", systemImage: "trash")
                    }
                }
        }
    }

    // MARK: - Add Button

    private var addTaskButton: some View {
        Button(action: onAdd) {
            Label("add_task", systemImage: "plus")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
        }
        .accessibilityLabel("Añadir tarea a \(column.name)")
    }

    // MARK: - Drop Handling

    private func handleDrop(items: [String]) -> Bool {
        guard let idString = items.first,
            let task = draggedTask,
            task.id.uuidString == idString
        else {
            return false
        }

        withAnimation(.snappy) {
            onDropTask(task)
        }
        return true
    }
}
