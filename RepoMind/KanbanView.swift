import SwiftData
import SwiftUI

// MARK: - View Mode

enum KanbanViewMode: String, CaseIterable {
    case board
    case list

    var icon: String {
        switch self {
        case .board: "rectangle.grid.1x2"
        case .list: "list.bullet"
        }
    }

    var accessibilityLabel: LocalizedStringKey {
        switch self {
        case .board: "Vista de tablero"
        case .list: "Vista de lista"
        }
    }
}

// MARK: - Kanban View

struct KanbanView: View {
    @Bindable var project: ProjectRepo
    @Environment(\.modelContext) private var context

    // ✅ FIX: Non-optional ViewModel initialized in .task
    @State private var viewModel: KanbanViewModel?
    @State private var viewMode: KanbanViewMode = .board
    @State private var sortedColumns: [KanbanColumn] = []

    var body: some View {
        Group {
            if let viewModel {
                kanbanContent(viewModel: viewModel)
            } else {
                ProgressView()
                    .accessibilityLabel("Cargando tablero")
            }
        }
        .navigationTitle(project.name)
        .toolbar { toolbarContent }
        .task {
            initializeViewModel()
        }
        // ✅ FIX: Use count as proxy for relationship changes
        .onChange(of: project.columns?.count) { _, _ in
            updateSortedColumns()
        }
    }

    // MARK: - Initialization

    private func initializeViewModel() {
        guard viewModel == nil else { return }

        let vm = KanbanViewModel(project: project, modelContext: context)
        vm.initializeDefaultColumnsIfNeeded()
        viewModel = vm
        updateSortedColumns()

        Task {
            await vm.checkVoicePermissions()
        }
    }

    private func updateSortedColumns() {
        sortedColumns = (project.columns ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack {
                viewModeToggle
                addColumnButton
            }
        }
    }

    // ✅ FIX: Use Label for accessibility
    private var viewModeToggle: some View {
        Button {
            withAnimation(.snappy) {
                viewMode = viewMode == .board ? .list : .board
            }
        } label: {
            Label(
                viewMode == .board ? "Cambiar a lista" : "Cambiar a tablero",
                systemImage: viewMode == .board ? "list.bullet" : "rectangle.grid.1x2"
            )
            .labelStyle(.iconOnly)
        }
        .accessibilityLabel(
            viewMode == .board ? "Cambiar a vista de lista" : "Cambiar a vista de tablero")
    }

    private var addColumnButton: some View {
        Button {
            viewModel?.showAddColumnSheet = true
        } label: {
            Label("Añadir Columna", systemImage: "rectangle.stack.badge.plus")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Añadir nueva columna")
    }

    // MARK: - Content

    @ViewBuilder
    private func kanbanContent(viewModel: KanbanViewModel) -> some View {
        @Bindable var viewModel = viewModel

        Group {
            switch viewMode {
            case .board:
                KanbanBoardView(viewModel: viewModel, sortedColumns: sortedColumns)
            case .list:
                KanbanListView(viewModel: viewModel, sortedColumns: sortedColumns)
            }
        }
        .sheet(item: $viewModel.editingTask) { task in
            TaskEditSheet(task: task, columns: sortedColumns)
        }
        .sheet(isPresented: $viewModel.showAddTaskSheet) {
            AddTaskSheet(
                content: $viewModel.newTaskContent,
                columns: sortedColumns,
                preselectedColumn: viewModel.targetColumnForNewTask
            ) { content, column in
                viewModel.createTask(content: content, column: column)
            }
        }
        .alert("new_column_title", isPresented: $viewModel.showAddColumnSheet) {
            TextField("column_name_placeholder", text: $viewModel.newColumnName)
            Button("cancel_button", role: .cancel) {
                viewModel.newColumnName = ""
            }
            Button("create_button") {
                viewModel.createColumn()
                updateSortedColumns()
            }
        }
        .alert("rename_column_title", isPresented: $viewModel.showRenameColumnAlert) {
            TextField("column_name_placeholder", text: $viewModel.renameColumnText)
            Button("cancel_button", role: .cancel) {
                viewModel.renameColumnText = ""
                viewModel.columnToRename = nil
            }
            Button("save_button") {
                viewModel.renameColumn()
            }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: ProjectRepo.self, TaskItem.self, KanbanColumn.self, configurations: config)

    let project = ProjectRepo(repoID: 1, name: "Preview Project", repoDescription: "Test")
    container.mainContext.insert(project)

    return NavigationStack {
        KanbanView(project: project)
    }
    .modelContainer(container)
}
