import SwiftData
import SwiftUI
import UIKit

struct KanbanColumnView: View {
    @Bindable var column: KanbanColumn
    @Binding var draggedTask: TaskItem?

    let onDropTask: (TaskItem, Int?) -> Void  // Ahora incluye índice destino
    let onAdd: () -> Void
    let onEditTask: (TaskItem) -> Void
    let onDeleteTask: (TaskItem) -> Void
    let onDeleteColumn: () -> Void
    let onRenameColumn: () -> Void
    let onMoveTask: (TaskItem) -> Void  // Nuevo: para mover con botón
    let onCheckboxTask: (TaskItem) -> Void  // Mover a columna "done"
    let isDoneColumn: Bool  // Si esta columna es la columna "done"

    @State private var isTargeted = false
    @State private var dropTargetIndex: Int? = nil

    @Query private var tasks: [TaskItem]

    init(
        column: KanbanColumn,
        draggedTask: Binding<TaskItem?>,
        onDropTask: @escaping (TaskItem, Int?) -> Void,
        onAdd: @escaping () -> Void,
        onEditTask: @escaping (TaskItem) -> Void,
        onDeleteTask: @escaping (TaskItem) -> Void,
        onDeleteColumn: @escaping () -> Void,
        onRenameColumn: @escaping () -> Void,
        onMoveTask: @escaping (TaskItem) -> Void,
        onCheckboxTask: @escaping (TaskItem) -> Void,
        isDoneColumn: Bool = false
    ) {
        self.column = column
        self._draggedTask = draggedTask
        self.onDropTask = onDropTask
        self.onAdd = onAdd
        self.onEditTask = onEditTask
        self.onDeleteTask = onDeleteTask
        self.onDeleteColumn = onDeleteColumn
        self.onRenameColumn = onRenameColumn
        self.onMoveTask = onMoveTask
        self.onCheckboxTask = onCheckboxTask
        self.isDoneColumn = isDoneColumn

        let columnID = column.persistentModelID
        let filter = #Predicate<TaskItem> { $0.column?.persistentModelID == columnID }
        _tasks = Query(filter: filter, sort: \TaskItem.orderIndex)
    }

    private var columnColor: Color {
        Color(hex: column.colorHex)
    }

    var body: some View {
        VStack(spacing: 0) {
            columnHeader

            if !column.isCollapsed {
                columnContent
                addTaskButton
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(
                    color: .black.opacity(isTargeted ? 0.2 : 0.08), radius: isTargeted ? 12 : 8,
                    y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isTargeted ? columnColor.opacity(0.5) : .clear, lineWidth: 2)
        )
    }

    // MARK: - Header con color estilo Trello

    private var columnHeader: some View {
        HStack(spacing: 12) {
            collapseButton

            Text(column.name)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            if !column.isCollapsed {
                taskCountBadge
            }

            columnMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(columnColor)
        .clipShape(
            .rect(
                topLeadingRadius: 16,
                bottomLeadingRadius: column.isCollapsed ? 16 : 0,
                bottomTrailingRadius: column.isCollapsed ? 16 : 0,
                topTrailingRadius: 16
            )
        )
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items: items, atIndex: 0)
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
            Image(systemName: column.isCollapsed ? "chevron.right" : "chevron.down")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(column.isCollapsed ? "expand_column" : "collapse_column")
    }

    private var taskCountBadge: some View {
        Text("\(tasks.count)")
            .font(.caption.weight(.bold))
            .foregroundStyle(columnColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.9), in: Capsule())
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
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(8)
        }
        .accessibilityLabel("column_options_label")
    }

    // MARK: - Content

    private var columnContent: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if tasks.isEmpty {
                    emptyColumnState
                } else {
                    tasksContent
                }
            }
            .padding(12)
        }
        .frame(maxHeight: .infinity)
        .background(Color(.secondarySystemBackground).opacity(0.5))
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items: items, atIndex: nil)
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.2)) {
                isTargeted = targeted
            }
        }
    }

    private var emptyColumnState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("drag_tasks_here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
    }

    private var tasksContent: some View {
        ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
            TaskCardEnhanced(
                task: task,
                columnColor: columnColor,
                isCompleted: isDoneColumn,
                onTap: { onEditTask(task) },
                onMove: { onMoveTask(task) },
                onDelete: { onDeleteTask(task) },
                onCheckbox: { onCheckboxTask(task) }
            )
            .contextMenu {
                Button {
                    onEditTask(task)
                } label: {
                    Label("edit_task", systemImage: "pencil")
                }
                Button {
                    onMoveTask(task)
                } label: {
                    Label("move_task", systemImage: "arrow.right.square")
                }
                Button {
                    onCheckboxTask(task)
                } label: {
                    Label(isDoneColumn ? "mark_pending" : "mark_done", systemImage: isDoneColumn ? "circle" : "checkmark.circle")
                }
                Divider()
                Button(role: .destructive) {
                    onDeleteTask(task)
                } label: {
                    Label("delete_task", systemImage: "trash")
                }
            }
            .draggable(task.id.uuidString) {
                TaskCardDragPreview(task: task, color: columnColor)
                    .onAppear { draggedTask = task }
            }
            .dropDestination(for: String.self) { items, _ in
                handleDrop(items: items, atIndex: index)
            } isTargeted: { targeted in
                if targeted {
                    dropTargetIndex = index
                } else if dropTargetIndex == index {
                    dropTargetIndex = nil
                }
            }
            .overlay(alignment: .top) {
                if dropTargetIndex == index {
                    Capsule()
                        .fill(columnColor)
                        .frame(height: 3)
                        .offset(y: -6)
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Add Button

    private var addTaskButton: some View {
        Button(action: onAdd) {
            HStack {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.medium))
                Text("add_task")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemBackground).opacity(0.5))
        }
        .buttonStyle(.plain)
        .clipShape(.rect(bottomLeadingRadius: 16, bottomTrailingRadius: 16))
        .accessibilityLabel(String(format: String(localized: "kanban_add_task_to %@"), column.name))
    }

    // MARK: - Drop Handling

    private func handleDrop(items: [String], atIndex index: Int?) -> Bool {
        guard let idString = items.first,
            let task = draggedTask,
            task.id.uuidString == idString
        else {
            return false
        }

        withAnimation(.snappy) {
            onDropTask(task, index)
        }
        dropTargetIndex = nil
        return true
    }
}

// MARK: - Enhanced Task Card con tap para editar

struct TaskCardEnhanced: View {
    let task: TaskItem
    let columnColor: Color
    let isCompleted: Bool
    let onTap: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void
    let onCheckbox: () -> Void

    @State private var showFullPhoto = false

    var body: some View {
        HStack(spacing: 10) {
            // Checkbox
            Button(action: isCompleted ? {} : onCheckbox) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isCompleted ? Color.green : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isCompleted)

            // Indicador de color
            RoundedRectangle(cornerRadius: 2)
                .fill(columnColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.content)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    // Without this, a task that never reached GitHub looked identical to one
                    // that did.
                    if task.needsIssueSync {
                        Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90.icloud")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("task_pending_sync")
                    }

                    if task.imagePath != nil || task.imageData != nil {
                        Button {
                            showFullPhoto = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "photo.fill")
                                    .font(.caption)
                                Text("photo_badge")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                }
            }

            Spacer(minLength: 0)

            // Botón para mover rápidamente a otra columna
            Button(action: onMove) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { onTap() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(task.content)
        .accessibilityHint("task_edit_hint")
        .sheet(isPresented: $showFullPhoto) {
            if let image = TaskImageHelper.fullImage(from: task) {
                FullPhotoView(image: image)
            }
        }
    }
}

// MARK: - Full Photo View

struct FullPhotoView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.85))
                .ignoresSafeArea()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("done_button") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink(
                            item: TransferableImage(image: image),
                            preview: SharePreview(
                                String(localized: "photo_section_header"),
                                image: Image(uiImage: image)
                            )
                        ) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Drag Preview (mejorado visualmente)

struct TaskCardDragPreview: View {
    let task: TaskItem
    let color: Color

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var previewWidth: CGFloat {
        horizontalSizeClass == .regular ? 280 : 300
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.content)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if task.imagePath != nil {
                        Image(systemName: "photo.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: previewWidth)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemBackground))
                .shadow(color: color.opacity(0.3), radius: 16, y: 8)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color, lineWidth: 2)
        )
        .rotationEffect(.degrees(-2))
        .scaleEffect(1.02)
    }
}
