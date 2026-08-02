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
        .onAppear { viewModel.updateVoiceContextualStrings() }
        .onChange(of: sortedColumns) { viewModel.updateVoiceContextualStrings() }
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
        let doneColumnID = viewModel.doneColumn(from: (viewModel.project.columns ?? []))?.id
        let isThisDoneColumn = column.id == doneColumnID

        VStack(alignment: .leading, spacing: 12) {
            columnHeader(for: column)

            if !tasks.isEmpty {
                if horizontalSizeClass == .regular {
                    // iPad/Mac: Grid layout
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(tasks) { task in
                            ListTaskCard(
                                task: task,
                                columnColor: Color(hex: column.colorHex),
                                isCompleted: isThisDoneColumn,
                                onCheckbox: { viewModel.moveTaskToDoneColumn(task) }
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
                                columnColor: Color(hex: column.colorHex),
                                isCompleted: isThisDoneColumn,
                                onCheckbox: { viewModel.moveTaskToDoneColumn(task) }
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
    let isCompleted: Bool
    let onCheckbox: () -> Void
    let onTap: () -> Void

    @State private var showFullPhoto = false

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: isCompleted ? {} : onCheckbox) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isCompleted ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isCompleted)

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
                    if task.imagePath != nil || task.imageData != nil {
                        Button {
                            showFullPhoto = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "photo.fill")
                                    .font(.caption2)
                                Text("photo_badge")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
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

                    Text(shortDate(task.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { onTap() }
        .sheet(isPresented: $showFullPhoto) {
            if let image = TaskImageHelper.fullImage(from: task) {
                FullPhotoView(image: image)
            }
        }
    }

    private func shortDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
