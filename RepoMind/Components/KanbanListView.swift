import SwiftData
import SwiftUI
import UIKit

struct KanbanListView: View {
    @Bindable var viewModel: KanbanViewModel
    var sortedColumns: [KanbanColumn]

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 300), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(sortedColumns) { column in
                    KanbanListColumnSection(viewModel: viewModel, column: column)
                }
            }
            .padding(.vertical)
            .padding(.bottom, 100)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottomTrailing) {
            VoiceFAB(voiceManager: viewModel.voiceManager) {
                viewModel.createTaskFromVoice()
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
    }

}

// MARK: - Column Section with Explicit Query

struct KanbanListColumnSection: View {
    @Bindable var viewModel: KanbanViewModel
    @Bindable var column: KanbanColumn

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var tasks: [TaskItem]

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 300), spacing: 12)]
    }

    init(viewModel: KanbanViewModel, column: KanbanColumn) {
        self.viewModel = viewModel
        self.column = column
        let columnID = column.persistentModelID
        let filter = #Predicate<TaskItem> { $0.column?.persistentModelID == columnID }
        _tasks = Query(filter: filter, sort: \TaskItem.orderIndex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            columnHeader(for: column)

            if !tasks.isEmpty {
                if horizontalSizeClass == .regular {
                    // iPad/Mac: Grid layout
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(tasks) { task in
                            ListTaskCard(
                                task: task,
                                columnColor: Color(hex: column.colorHex)
                            ) {
                                viewModel.editingTask = task
                            }
                        }
                    }
                } else {
                    // iPhone: VStack
                    VStack(spacing: 8) {
                        ForEach(tasks) { task in
                            ListTaskCard(
                                task: task,
                                columnColor: Color(hex: column.colorHex)
                            ) {
                                viewModel.editingTask = task
                            }
                        }
                    }
                }
            } else {
                emptyColumnPlaceholder
            }
        }
        .padding(.horizontal)
    }

    private func columnHeader(for column: KanbanColumn) -> some View {
        HStack(spacing: 12) {
            // Indicador de color
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: column.colorHex))
                .frame(width: 4, height: 24)

            Text(column.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Text("\(tasks.count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(hex: column.colorHex))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color(hex: column.colorHex).opacity(0.15), in: Capsule())

            Spacer()

            // Botón para añadir tarea
            Button {
                viewModel.prepareAddTask(for: column)
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: column.colorHex))
                    .padding(8)
                    .background(Color(hex: column.colorHex).opacity(0.1), in: Circle())
            }
        }
        .padding(.vertical, 8)
    }

    private var emptyColumnPlaceholder: some View {
        HStack {
            Image(systemName: "tray")
                .foregroundStyle(.tertiary)
            Text("no_tasks")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - List Task Card (diseño mejorado para vista lista)

struct ListTaskCard: View {
    let task: TaskItem
    let columnColor: Color
    let onTap: () -> Void

    @State private var thumbnailImage: UIImage?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Indicador de color lateral
                RoundedRectangle(cornerRadius: 2)
                    .fill(columnColor)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text(task.content)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 12) {
                        if (task.imagePath != nil || task.imageData != nil) && thumbnailImage == nil {
                            HStack(spacing: 4) {
                                Image(systemName: "photo.fill")
                                    .font(.caption2)
                                Text("photo_badge")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.blue)
                        }

                        if task.audioPath != nil {
                            HStack(spacing: 4) {
                                Image(systemName: "waveform")
                                    .font(.caption2)
                                Text("audio_badge")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.purple)
                        }

                        Spacer()

                        Text(task.createdAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: 0)

                if let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
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
                                        UIPasteboard.general.setData(
                                            data, forPasteboardType: "public.png")
                                    }
                                    ToastManager.shared.show(
                                        String(localized: "image_copied_toast"), style: .success)
                                } label: {
                                    Label("copy_image", systemImage: "doc.on.doc")
                                }
                            }
                        }
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
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
            from: task, size: CGSize(width: 120, height: 120))
    }
}
