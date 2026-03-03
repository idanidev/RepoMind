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
        onMoveTask: @escaping (TaskItem) -> Void
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
                onTap: { onEditTask(task) },
                onMove: { onMoveTask(task) },
                onDelete: { onDeleteTask(task) }
            )
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
        .accessibilityLabel(String(format: String(localized: "Add task to %@"), column.name))
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
    let onTap: () -> Void
    let onMove: () -> Void
    let onDelete: () -> Void

    @State private var thumbnailImage: UIImage?

    var body: some View {
        // Tap para editar directamente (sin context menu)
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Miniatura de imagen si existe
                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 80)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onDrag { NSItemProvider(object: fullTaskImage ?? image) }
                        .contextMenu {
                            if let img = fullTaskImage {
                                ShareLink(
                                    item: TransferableImage(image: img),
                                    preview: SharePreview(task.content, image: Image(uiImage: img))
                                ) {
                                    Label("share_image", systemImage: "square.and.arrow.up")
                                }
                                Button {
                                    if let data = img.pngData() {
                                        UIPasteboard.general.setData(data, forPasteboardType: "public.png")
                                    }
                                    ToastManager.shared.show(
                                        String(localized: "image_copied_toast"), style: .success)
                                } label: {
                                    Label("copy_image", systemImage: "doc.on.doc")
                                }
                            }
                        }
                }

                HStack(spacing: 10) {
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

                        // Indicadores de adjuntos
                        HStack(spacing: 8) {
                            if (task.imagePath != nil || task.imageData != nil)
                                && thumbnailImage == nil
                            {
                                // Solo mostrar badge si no hay miniatura cargada
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

                            if task.audioPath != nil {
                                HStack(spacing: 4) {
                                    Image(systemName: "waveform")
                                        .font(.caption)
                                    Text("audio_badge")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.purple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.purple.opacity(0.1), in: Capsule())
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
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(task.content)
        .accessibilityHint("task_edit_hint")
        .task {
            await loadThumbnail()
        }
        .onChange(of: task.imageData) { _, _ in
            thumbnailImage = nil
            Task { await loadThumbnail() }
        }
    }

    private var fullTaskImage: UIImage? {
        TaskImageHelper.fullImage(from: task)
    }

    private func loadThumbnail() async {
        thumbnailImage = await TaskImageHelper.loadThumbnail(
            from: task, size: CGSize(width: 400, height: 200))
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
                    if task.audioPath != nil {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundStyle(.purple)
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
