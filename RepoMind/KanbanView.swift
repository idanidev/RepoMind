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
    @Query private var feedbackIssues: [FeedbackIssue]

    // ✅ FIX: Non-optional ViewModel initialized in .task
    @State private var viewModel: KanbanViewModel?
    @State private var viewMode: KanbanViewMode = .board
    @State private var showPaywall = false
    @State private var showRepoSettings = false
    @State private var showFeedback = false
    @State private var showSyncDisabledAlert = false

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
        await vm.reconcileGitHubSyncIfNeeded()
        if project.syncTasksDisabledReason != nil {
            showSyncDisabledAlert = true
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack {
                viewModeToggle
                feedbackButton
                addColumnButton
                repoSettingsButton
            }
        }
    }

    private var feedbackButton: some View {
        let unread = project.unreadFeedbackCount(in: feedbackIssues)
        return Button {
            showFeedback = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                if unread > 0 {
                    Text("\(unread)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.red, in: Capsule())
                        .offset(x: 8, y: -8)
                }
            }
        }
        .accessibilityLabel("feedback_open_button")
    }

    private var repoSettingsButton: some View {
        Button {
            showRepoSettings = true
        } label: {
            Label("repo_settings", systemImage: "gearshape")
                .labelStyle(.iconOnly)
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
            TaskEditSheet(task: task, columns: columns) { editedTask, previousColumn in
                viewModel.handleTaskEdited(editedTask, previousColumn: previousColumn)
            }
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
        .sheet(isPresented: $showRepoSettings) {
            RepoSettingsSheet(viewModel: viewModel, columns: columns)
        }
        .sheet(isPresented: $showFeedback) {
            NavigationStack { FeedbackView(repo: project) }
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
        .alert("sync_tasks_disabled_alert_title", isPresented: $showSyncDisabledAlert) {
            Button("ok") { project.syncTasksDisabledReason = nil }
        } message: {
            Text(project.syncTasksDisabledReason ?? "")
        }
    }
}

// MARK: - Repo Settings Sheet

struct RepoSettingsSheet: View {
    let viewModel: KanbanViewModel
    let columns: [KanbanColumn]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var selectedDoneColumn: KanbanColumn?
    @State private var showBulkSyncConfirm = false
    @AppStorage("isDemoMode") private var isDemoMode = false

    private var repo: ProjectRepo { viewModel.project }

    private var canSyncTasks: Bool {
        !repo.isLocal && repo.account != nil && !isDemoMode
    }

    private var repoFullName: String {
        guard let url = URL(string: repo.htmlURL) else { return repo.name }
        let owner = url.pathComponents.filter { $0 != "/" }.first ?? ""
        return owner.isEmpty ? repo.name : "\(owner)/\(repo.name)"
    }

    private var syncToggleBinding: Binding<Bool> {
        Binding(
            get: { repo.syncTasksToGitHub },
            set: { newValue in
                guard newValue else {
                    repo.syncTasksToGitHub = false
                    return
                }
                let taskCount = repo.tasks?.count ?? 0
                if taskCount > 10 {
                    showBulkSyncConfirm = true
                } else {
                    repo.syncTasksToGitHub = true
                    repo.syncTasksDisabledReason = nil
                    Task { await enableSync() }
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedDoneColumn = nil
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "circle.slash")
                                .foregroundStyle(.secondary)
                            Text("checkbox_none")
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedDoneColumn == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }

                    ForEach(columns) { column in
                        Button {
                            selectedDoneColumn = column
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: column.colorHex))
                                    .frame(width: 12, height: 12)
                                Text(column.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedDoneColumn?.id == column.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                } header: {
                    Text("checkbox_done_column_section")
                } footer: {
                    Text("checkbox_done_column_footer")
                }

                if canSyncTasks {
                    Section {
                        Toggle("sync_tasks_github_toggle", isOn: syncToggleBinding)
                        if let reason = repo.syncTasksDisabledReason, !repo.syncTasksToGitHub {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    } header: {
                        Text("sync_tasks_github_section")
                    } footer: {
                        Text(String(format: String(localized: "sync_tasks_github_footer %@"), repoFullName))
                    }
                }
            }
            .navigationTitle("repo_settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") {
                        viewModel.setDoneColumn(selectedDoneColumn)
                        dismiss()
                    }
                }
            }
            .onAppear {
                selectedDoneColumn = viewModel.doneColumn(from: columns)
            }
            .alert("sync_tasks_confirm_bulk_title", isPresented: $showBulkSyncConfirm) {
                Button("cancel_button", role: .cancel) {}
                Button("sync_tasks_confirm_bulk_button") {
                    repo.syncTasksToGitHub = true
                    repo.syncTasksDisabledReason = nil
                    Task { await enableSync() }
                }
            } message: {
                Text(String(format: String(localized: "sync_tasks_confirm_bulk %lld"), repo.tasks?.count ?? 0))
            }
        }
        .presentationDetents([.medium])
        .frame(idealWidth: 400)
    }

    private func enableSync() async {
        guard let account = repo.account,
              let token = try? await KeychainManager.shared.retrieveToken(for: account.tokenKey)
        else { return }
        await TaskIssueSyncService.shared.ensureLabels(repo: repo, columns: columns, token: token)
        for task in repo.tasks ?? [] where task.issueNumber == nil {
            task.needsIssueSync = true
        }
        try? context.save()
        await TaskIssueSyncService.shared.reconcile(repo: repo, context: context, token: token)
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
