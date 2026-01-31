import SwiftData
import SwiftUI

struct KanbanListView: View {
    @Bindable var viewModel: KanbanViewModel
    var sortedColumns: [KanbanColumn]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(sortedColumns) {
                    column in
                    Section {
                        if let tasks = column.tasks, !tasks.isEmpty {
                            ForEach(tasks.sorted(by: { $0.createdAt > $1.createdAt })) { task in
                                TaskCard(task: task)
                                    .contextMenu {
                                        Button {
                                            viewModel.editingTask = task
                                        } label: {
                                            Label("edit_task", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            viewModel.deleteTask(task)
                                        } label: {
                                            Label("delete_task", systemImage: "trash")
                                        }
                                    }
                            }
                        } else {
                            Text("no_tasks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading)
                        }
                    } header: {
                        HStack {
                            Text(column.name)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("\(column.tasks?.count ?? 0)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())

                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)  // Sticky header look
                    }
                }
            }
            .padding()
            .padding(.bottom, 100)
        }
        .overlay(alignment: .bottomTrailing) {
            VoiceFAB(voiceManager: viewModel.voiceManager) {
                viewModel.createTaskFromVoice()
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
        }
    }
}
