import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var sortedTasks: [TaskItem] = []

    var body: some View {
        GlassEffectContainer(cornerRadius: 12) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        withAnimation {
                            column.isCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: column.isCollapsed ? "chevron.right" : "chevron.down")
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        column.isCollapsed ? "expand_column" : "collapse_column")

                    Text(column.name)
                        .font(.headline)

                    Spacer()

                    if !column.isCollapsed {
                        Text("\(column.tasks?.count ?? 0)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }

                    Menu {
                        Button(role: .destructive, action: onDeleteColumn) {
                            Label("delete_column", systemImage: "trash")
                        }

                        Button(action: onRenameColumn) {
                            Label("rename_column", systemImage: "pencil")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .padding(8)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .dropDestination(for: String.self) { items, _ in
                    guard let idString = items.first,
                        let task = draggedTask,
                        task.id.uuidString == idString
                    else { return false }
                    onDropTask(task)
                    return true
                } isTargeted: { targeted in
                    withAnimation { isTargeted = targeted }
                }

                // Tasks List
                if !column.isCollapsed {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if column.tasks?.isEmpty ?? true {
                                ContentUnavailableView {
                                    Label("column_empty", systemImage: "tray")
                                } description: {
                                    Text("drag_tasks_here")
                                }
                                .frame(height: 150)
                                .opacity(0.5)
                            } else {
                                ForEach(sortedTasks) { task in
                                    TaskCard(task: task)
                                        .contentShape(
                                            .dragPreview, RoundedRectangle(cornerRadius: 14)
                                        )
                                        .onDrag {
                                            draggedTask = task
                                            return NSItemProvider(
                                                object: task.id.uuidString as NSString)
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
                        }
                        .padding()
                    }
                    .frame(maxHeight: .infinity)
                    .shapeContentHittable()
                    .dropDestination(for: String.self) { items, _ in
                        guard let idString = items.first,
                            let task = draggedTask,
                            task.id.uuidString == idString
                        else { return false }

                        withAnimation(.snappy) {
                            onDropTask(task)
                        }
                        return true
                    } isTargeted: { targeted in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isTargeted = targeted
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
                    )
                }

                if !column.isCollapsed {
                    Button(action: onAdd) {
                        Label("add_task", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                    }
                }
            }
        }
        .shadow(color: Color.black.opacity(isTargeted ? 0.15 : 0.05), radius: 8, x: 0, y: 4)
        .task {
            updateSortedTasks()
        }
        .onChange(of: column.tasks) { _, _ in
            updateSortedTasks()
        }
    }

    private func updateSortedTasks() {
        sortedTasks = (column.tasks ?? []).sorted { $0.createdAt > $1.createdAt }
    }
}
