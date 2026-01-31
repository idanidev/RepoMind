import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Kanban View (Vertical Mobile-Friendly)

// MARK: - Kanban View (Vertical Mobile-Friendly)

struct KanbanView: View {
    @Bindable var project: ProjectRepo
    @State private var viewModel: KanbanViewModel?
    @State private var viewMode: ViewMode = .board
    @State private var sortedColumns: [KanbanColumn] = []

    enum ViewMode: String, CaseIterable {
        case board = "Tablero"
        case list = "Lista"
    }

    @Environment(\.modelContext) private var context
    // Removed @Query tasks - using relationships instead for performance

    init(project: ProjectRepo) {
        self.project = project
        // Tasks query removed
    }

    var body: some View {
        Group {
            if let viewModel {
                switch viewMode {
                case .board:
                    boardContent(viewModel: viewModel)
                case .list:
                    listContent(viewModel: viewModel)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(project.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    // View Toggle Button
                    Button(action: {
                        withAnimation {
                            viewMode = (viewMode == .board) ? .list : .board
                        }
                    }) {
                        Label(
                            "Cambiar Vista",
                            systemImage: viewMode == .board ? "list.bullet" : "rectangle.grid.1x2")
                    }
                    .accessibilityHint(
                        viewMode == .board
                            ? "Cambiar a vista de lista" : "Cambiar a vista de tablero")

                    Button(action: { viewModel?.showAddColumnSheet = true }) {
                        Label("Añadir Columna", systemImage: "rectangle.stack.badge.plus")
                    }
                }
            }
        }
        .sheet(
            item: Binding(
                get: { viewModel?.editingTask },
                set: { viewModel?.editingTask = $0 }
            )
        ) { task in
            TaskEditSheet(task: task, columns: sortedColumns)
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel?.showAddTaskSheet ?? false },
                set: { viewModel?.showAddTaskSheet = $0 }
            )
        ) {
            if let viewModel {
                @Bindable var vm = viewModel
                AddTaskSheet(
                    content: $vm.newTaskContent,
                    columns: sortedColumns,
                    preselectedColumn: viewModel.targetColumnForNewTask,
                    onSave: { content, column in
                        viewModel.createTask(content: content, column: column)
                    }
                )
            }
        }
        .alert(
            "Nueva Columna",
            isPresented: Binding(
                get: { viewModel?.showAddColumnSheet ?? false },
                set: { viewModel?.showAddColumnSheet = $0 }
            )
        ) {
            TextField(
                "Nombre de columna",
                text: Binding(
                    get: { viewModel?.newColumnName ?? "" },
                    set: { viewModel?.newColumnName = $0 }
                ))
            Button("Cancelar", role: .cancel) { viewModel?.newColumnName = "" }
            Button("Crear") {
                viewModel?.createColumn()
            }
        }
        .alert(
            "Renombrar Columna",
            isPresented: Binding(
                get: { viewModel?.showRenameColumnAlert ?? false },
                set: { viewModel?.showRenameColumnAlert = $0 }
            )
        ) {
            TextField(
                "Nombre de columna",
                text: Binding(
                    get: { viewModel?.renameColumnText ?? "" },
                    set: { viewModel?.renameColumnText = $0 }
                ))
            Button("Cancelar", role: .cancel) {
                viewModel?.renameColumnText = ""
                viewModel?.columnToRename = nil
            }
            Button("Guardar") {
                viewModel?.renameColumn()
            }
        }
        .task {
            if viewModel == nil {
                viewModel = KanbanViewModel(project: project, modelContext: context)
            }
            await viewModel?.checkVoicePermissions()
            viewModel?.initializeDefaultColumnsIfNeeded()
            updateSortedColumns()
        }
        .onChange(of: project.columns) { _, _ in
            updateSortedColumns()
        }
    }

    private func updateSortedColumns() {
        sortedColumns = (project.columns ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    private func boardContent(viewModel: KanbanViewModel) -> some View {
        KanbanBoardView(viewModel: viewModel, sortedColumns: sortedColumns)
    }

    private func listContent(viewModel: KanbanViewModel) -> some View {
        KanbanListView(viewModel: viewModel, sortedColumns: sortedColumns)
    }
}
