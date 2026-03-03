import SwiftData
import SwiftUI

struct KanbanBoardView: View {
    @Bindable var viewModel: KanbanViewModel
    var sortedColumns: [KanbanColumn]

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var currentPage: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            if horizontalSizeClass == .regular {
                // iPad/Mac: Horizontal scrolling multi-column
                regularLayout
            } else {
                // iPhone: Paged TabView
                compactLayout
            }
        }
        .overlay(alignment: .bottomTrailing) {
            VoiceFAB(voiceManager: viewModel.voiceManager) {
                viewModel.createTaskFromVoice()
            }
            .padding(.trailing, 20)
            .padding(.bottom, 60)
        }
        .sheet(isPresented: $viewModel.showMoveSheet) {
            if let task = viewModel.taskToMove {
                MoveTaskSheet(
                    task: task,
                    columns: sortedColumns,
                    onMove: { column in
                        viewModel.moveTask(task, to: column, atIndex: nil)
                        viewModel.showMoveSheet = false
                        viewModel.taskToMove = nil
                    }
                )
            }
        }
    }

    // MARK: - Regular Layout (iPad/Mac)

    private var regularLayout: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                ForEach(sortedColumns) { column in
                    KanbanColumnView(
                        column: column,
                        draggedTask: $viewModel.draggingTask,
                        onDropTask: { task, index in
                            viewModel.moveTask(task, to: column, atIndex: index)
                        },
                        onAdd: { viewModel.prepareAddTask(for: column) },
                        onEditTask: { task in viewModel.editingTask = task },
                        onDeleteTask: { task in viewModel.deleteTask(task) },
                        onDeleteColumn: { viewModel.deleteColumn(column) },
                        onRenameColumn: { viewModel.startRenaming(column) },
                        onMoveTask: { task in viewModel.showMoveTaskSheet(task) }
                    )
                    .frame(width: 320)
                    .frame(maxHeight: .infinity)
                }

                // Add column button
                Button(action: { viewModel.showAddColumnSheet = true }) {
                    VStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("add_column")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 320, height: 180)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground).opacity(0.5))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                            .foregroundStyle(.tertiary)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Compact Layout (iPhone)

    private var compactLayout: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(Array(sortedColumns.enumerated()), id: \.element.id) { index, column in
                    columnPage(for: column)
                        .tag(index)
                }
                addColumnPage
                    .tag(sortedColumns.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            pageIndicator
                .padding(.bottom, 8)
        }
        .onAppear {
            // Inicializar con la primera columna visible
            if !sortedColumns.isEmpty {
                viewModel.currentColumn = sortedColumns[0]
            }
        }
        .onChange(of: currentPage) { _, newPage in
            // Actualizar la columna activa cuando el usuario desliza
            if newPage < sortedColumns.count {
                viewModel.currentColumn = sortedColumns[newPage]
            }
        }
        .onChange(of: sortedColumns) { _, columns in
            // Si las columnas cambian (ej. se añade una), mantener consistencia
            if currentPage < columns.count {
                viewModel.currentColumn = columns[currentPage]
            }
        }
    }

    // MARK: - Column Page

    private func columnPage(for column: KanbanColumn) -> some View {
        GeometryReader { geometry in
            KanbanColumnView(
                column: column,
                draggedTask: $viewModel.draggingTask,
                onDropTask: { task, index in
                    viewModel.moveTask(task, to: column, atIndex: index)
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
                },
                onMoveTask: { task in
                    viewModel.showMoveTaskSheet(task)
                }
            )
            .frame(width: geometry.size.width - 32)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Add Column Page

    private var addColumnPage: some View {
        GeometryReader { geometry in
            Button(action: { viewModel.showAddColumnSheet = true }) {
                VStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("add_column")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(width: geometry.size.width - 32, height: 180)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground).opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .foregroundStyle(.tertiary)
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .accessibilityLabel("add_new_column_button")
        .accessibilityHint("add_new_column_hint")
    }

    // MARK: - Page Indicator (Dots)

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<sortedColumns.count + 1, id: \.self) { index in
                Circle()
                    .fill(currentPage == index ? Color.primary : Color.primary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(currentPage == index ? 1.2 : 1.0)
                    .animation(.spring(duration: 0.3), value: currentPage)
                    .onTapGesture {
                        withAnimation {
                            currentPage = index
                        }
                    }
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Move Task Sheet

struct MoveTaskSheet: View {
    let task: TaskItem
    let columns: [KanbanColumn]
    let onMove: (KanbanColumn) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(columns) { column in
                    Button {
                        onMove(column)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: column.colorHex))
                                .frame(width: 12, height: 12)

                            Text(column.name)
                                .foregroundStyle(.primary)

                            Spacer()

                            if task.column?.id == column.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }

                            Text("\(column.tasks?.count ?? 0)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                    .disabled(task.column?.id == column.id)
                }
            }
            .navigationTitle("move_task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
