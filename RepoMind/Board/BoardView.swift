import SwiftData
import SwiftUI

// MARK: - Board

/// The project screen on iPhone: one column per page, cards on pure black, the add bar and the
/// microphone at the bottom.
///
/// Built on `KanbanViewModel`, so every mutation — and the GitHub issue it mirrors — goes
/// through the same code as the classic board, which iPad and Mac keep.
struct BoardView: View {
    @Bindable var project: ProjectRepo
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var columns: [KanbanColumn]
    @Query private var feedbackIssues: [FeedbackIssue]

    @State private var viewModel: KanbanViewModel?
    @State private var page = 0
    @State private var showPaywall = false
    @State private var showRepoSettings = false
    @State private var showFeedback = false
    @State private var showStats = false
    @State private var showSyncDisabledAlert = false

    init(project: ProjectRepo) {
        self.project = project
        let projectID = project.persistentModelID
        let filter = #Predicate<KanbanColumn> { $0.project?.persistentModelID == projectID }
        _columns = Query(filter: filter, sort: \KanbanColumn.orderIndex)
    }

    var body: some View {
        ZStack {
            HomeTheme.background
                .ignoresSafeArea()
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView()
                    .accessibilityLabel("loading_board")
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: project.repoID) {
            await initializeViewModel()
        }
    }

    /// Same as the classic board: a fresh view model per project, default columns if the board
    /// is new, voice permissions, then whatever GitHub closed while the user was away.
    private func initializeViewModel() async {
        let model = KanbanViewModel(project: project, modelContext: context)
        model.initializeDefaultColumnsIfNeeded()
        viewModel = model
        await model.checkVoicePermissions()
        await model.reconcileGitHubSyncIfNeeded()
        if project.syncTasksDisabledReason != nil {
            showSyncDisabledAlert = true
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ viewModel: KanbanViewModel) -> some View {
        @Bindable var viewModel = viewModel
        let summary = HomeRepoCardData(repo: project)
        let doneID = viewModel.doneColumn(from: columns)?.id

        VStack(spacing: 0) {
            header(summary, viewModel: viewModel)
            BoardColumnPills(
                columns: columns,
                selection: $page,
                onAddColumn: { addColumn(viewModel) },
                onRename: { viewModel.startRenaming($0) },
                onDelete: { viewModel.deleteColumn($0) }
            )
            .padding(.vertical, 10)
            TabView(selection: $page) {
                ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                    BoardColumnPage(column: column, isDoneColumn: column.id == doneID, viewModel: viewModel)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            BoardPageDots(count: columns.count, selection: $page)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar(viewModel)
        }
        .onAppear {
            viewModel.updateVoiceContextualStrings()
            syncCurrentColumn(viewModel)
        }
        .onChange(of: page) { _, _ in syncCurrentColumn(viewModel) }
        .onChange(of: columns) { _, _ in
            viewModel.updateVoiceContextualStrings()
            syncCurrentColumn(viewModel)
        }
        .sheet(item: $viewModel.editingTask) { task in
            TaskEditSheet(
                task: task,
                columns: columns,
                onSave: { editedTask, previousColumn in
                    viewModel.handleTaskEdited(editedTask, previousColumn: previousColumn)
                },
                onDelete: { deletedTask in
                    viewModel.deleteTask(deletedTask)
                }
            )
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
        .sheet(isPresented: $viewModel.showMoveSheet) {
            if let task = viewModel.taskToMove {
                MoveTaskSheet(task: task, columns: columns) { column in
                    viewModel.moveTask(task, to: column, atIndex: nil)
                    viewModel.showMoveSheet = false
                    viewModel.taskToMove = nil
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showRepoSettings) {
            RepoSettingsSheet(viewModel: viewModel, columns: columns)
        }
        .sheet(item: $viewModel.pendingCapture) { _ in
            VoiceCaptureSheet(viewModel: viewModel, columns: columns.map(\.name))
        }
        .sheet(isPresented: $showFeedback) {
            NavigationStack { FeedbackView(repo: project) }
        }
        .navigationDestination(isPresented: $showStats) {
            BoardStatsView(project: project)
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

    // MARK: Header

    private func header(_ summary: HomeRepoCardData, viewModel: KanbanViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                BoardCircleButton(symbol: "chevron.left", label: "back_button") { dismiss() }
                Spacer()
                BoardProgressRing(progress: progress(summary))
                BoardCircleButton(
                    symbol: "bubble.left.and.exclamationmark.bubble.right",
                    label: "feedback_open_button",
                    badge: project.unreadFeedbackCount(in: feedbackIssues)
                ) { showFeedback = true }
                Menu {
                    Button {
                        addColumn(viewModel)
                    } label: {
                        Label("add_column", systemImage: "rectangle.stack.badge.plus")
                    }
                    if !project.isLocal {
                        Button {
                            showStats = true
                        } label: {
                            Label("stats_menu_item", systemImage: "chart.bar")
                        }
                    }
                    Button {
                        showRepoSettings = true
                    } label: {
                        Label("repo_settings", systemImage: "gearshape")
                    }
                } label: {
                    BoardCircleButton.face(symbol: "ellipsis")
                }
                .accessibilityLabel("more_options")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(HomeTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle(summary))
                    .font(.subheadline)
                    .foregroundStyle(HomeTheme.textSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, HomeTheme.gutter)
        .padding(.top, 6)
    }

    private func progress(_ summary: HomeRepoCardData) -> Double {
        guard summary.tasksTotal > 0 else { return 0 }
        return Double(summary.tasksTotal - summary.tasksPending) / Double(summary.tasksTotal)
    }

    /// "18 pending • 2 unpublished": the second part only while something is stuck.
    private func subtitle(_ summary: HomeRepoCardData) -> String {
        var parts = [String(format: String(localized: "home_stat_pending %lld"), summary.tasksPending)]
        if summary.unpublished > 0 {
            parts.append(String(format: String(localized: "home_stat_unpublished %lld"), summary.unpublished))
        }
        return parts.joined(separator: " • ")
    }

    // MARK: Bottom bar

    private func bottomBar(_ viewModel: KanbanViewModel) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            Button {
                guard let column = viewModel.currentColumn ?? columns.first else { return }
                viewModel.prepareAddTask(for: column)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("add_task")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(HomeTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(HomeTheme.surface))
                .overlay(Capsule().strokeBorder(HomeTheme.hairline, lineWidth: 0.5))
            }
            .buttonStyle(HomeCardButtonStyle())
            VoiceFAB(voiceManager: viewModel.voiceManager) {
                viewModel.prepareCapture()
            }
        }
        .padding(.horizontal, HomeTheme.gutter)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(
            LinearGradient(
                colors: [HomeTheme.background.opacity(0), HomeTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: Helpers

    private func addColumn(_ viewModel: KanbanViewModel) {
        let currentCount = project.columns?.count ?? 0
        if SubscriptionManager.shared.canAddKanbanColumn(currentCount: currentCount) {
            viewModel.showAddColumnSheet = true
        } else {
            showPaywall = true
        }
    }

    /// Keeps the voice capture's target in step with the visible page, and the page inside the
    /// columns that still exist after one is deleted.
    private func syncCurrentColumn(_ viewModel: KanbanViewModel) {
        if page >= columns.count {
            page = max(0, columns.count - 1)
        }
        if page < columns.count {
            viewModel.currentColumn = columns[page]
        }
    }
}
