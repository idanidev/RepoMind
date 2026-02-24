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
        case .board: "board_view_label"
        case .list: "list_view_label"
        }
    }
}

// MARK: - Kanban View

struct KanbanView: View {
    @Bindable var project: ProjectRepo
    @Environment(\.modelContext) private var context

    @Query private var columns: [KanbanColumn]

    // ✅ FIX: Non-optional ViewModel initialized in .task
    @State private var viewModel: KanbanViewModel?
    @State private var viewMode: KanbanViewMode = .board
    @State private var showPaywall = false

    init(project: ProjectRepo) {
        self.project = project
        let projectID = project.persistentModelID
        let filter = #Predicate<KanbanColumn> { $0.project?.persistentModelID == projectID }
        _columns = Query(filter: filter, sort: \KanbanColumn.orderIndex)
    }

    var body: some View {
        Group {
            if let viewModel {
                kanbanContent(viewModel: viewModel)
            } else {
                ProgressView()
                    .accessibilityLabel("loading_board")
            }
        }
        .navigationTitle(project.name)
        .toolbar { toolbarContent }
        .task(id: project.repoID) {
            await initializeViewModel()
        }
    }

    // MARK: - Initialization

    private func initializeViewModel() async {
        // Always create a fresh VM — .task(id:) ensures this only runs when the project changes
        // Making this async lets checkVoicePermissions participate in structured concurrency:
        // if the user switches projects quickly, the task is cancelled automatically.
        let vm = KanbanViewModel(project: project, modelContext: context)
        vm.initializeDefaultColumnsIfNeeded()
        viewModel = vm
        await vm.checkVoicePermissions()
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
                viewMode == .board ? "switch_to_list" : "switch_to_board",
                systemImage: viewMode == .board ? "list.bullet" : "rectangle.grid.1x2"
            )
            .labelStyle(.iconOnly)
        }
        .accessibilityLabel(
            viewMode == .board ? "switch_to_list_hint" : "switch_to_board_hint")
    }

    private var addColumnButton: some View {
        Button {
            let currentCount = project.columns?.count ?? 0
            if SubscriptionManager.shared.canAddKanbanColumn(currentCount: currentCount) {
                viewModel?.showAddColumnSheet = true
            } else {
                showPaywall = true
            }
        } label: {
            Label("add_column", systemImage: "rectangle.stack.badge.plus")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("add_new_column_button")
    }

    // MARK: - Content

    @ViewBuilder
    private func kanbanContent(viewModel: KanbanViewModel) -> some View {
        @Bindable var viewModel = viewModel

        Group {
            switch viewMode {
            case .board:
                KanbanBoardView(viewModel: viewModel, sortedColumns: columns)
            case .list:
                KanbanListView(viewModel: viewModel, sortedColumns: columns)
            }
        }
        .sheet(item: $viewModel.editingTask) { task in
            TaskEditSheet(task: task, columns: columns)
        }
        .sheet(isPresented: $viewModel.showAddTaskSheet) {
            AddTaskSheet(
                content: $viewModel.newTaskContent,
                columns: columns,
                preselectedColumn: viewModel.targetColumnForNewTask
            ) { content, column, imageData in
                viewModel.createTask(content: content, column: column, imageData: imageData)
            }
        }
        .alert("new_column_title", isPresented: $viewModel.showAddColumnSheet) {
            TextField("column_name_placeholder", text: $viewModel.newColumnName)
            Button("cancel_button", role: .cancel) {
                viewModel.newColumnName = ""
            }
            Button("create_button") {
                if !viewModel.createColumn() {
                    showPaywall = true
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
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
    let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try! ModelContainer(
        for: ProjectRepo.self, TaskItem.self, KanbanColumn.self, configurations: config)

    let project = ProjectRepo(repoID: 1, name: "Preview Project", repoDescription: "Test")
    container.mainContext.insert(project)

    return NavigationStack {
        KanbanView(project: project)
    }
    .modelContainer(container)
}
