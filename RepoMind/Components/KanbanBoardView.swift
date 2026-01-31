import SwiftData
import SwiftUI

struct KanbanBoardView: View {
    @Bindable var viewModel: KanbanViewModel
    var sortedColumns: [KanbanColumn]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(sortedColumns) { column in
                    KanbanColumnView(
                        column: column,
                        draggedTask: $viewModel.draggingTask,
                        onDropTask: { task in
                            viewModel.moveTask(task, to: column)
                        },
                        onAdd: {
                            viewModel.prepareAddTask(for: column)
                        },
                        onEditTask: { task in
                            viewModel.editingTask = task
                        },
                        onDeleteTask: { task in
                            viewModel.deleteTask(task)
                        },
                        onDeleteColumn: {
                            viewModel.deleteColumn(column)
                        },
                        onRenameColumn: {
                            viewModel.startRenaming(column)
                        }
                    )
                    .frame(width: 320)
                }

                // Add Column Button
                addColumnButton
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

    private var addColumnButton: some View {
        Button(action: { viewModel.showAddColumnSheet = true }) {
            GlassEffectContainer(cornerRadius: 12) {
                VStack {
                    Image(systemName: "plus")
                        .font(.largeTitle)
                    Text("add_column")
                        .font(.headline)
                }
                .frame(width: 320, height: 200)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                    .foregroundStyle(.secondary)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("add_new_column_button")
        .accessibilityHint("add_new_column_hint")
    }
}
