import SwiftData
import SwiftUI

/// Global "quick add" sheet triggered by the Home Screen Quick Action (long-press the app icon).
/// Lets the user pick any repo + column and drop a task in without navigating the full board.
struct QuickAddTaskView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ProjectRepo.updatedAt, order: .reverse) private var allRepos: [ProjectRepo]

    @State private var selectedRepo: ProjectRepo?
    @State private var selectedColumn: KanbanColumn?
    @State private var content: String = ""
    @FocusState private var isContentFocused: Bool

    private var repos: [ProjectRepo] {
        allRepos.filter { !$0.isArchived }
    }

    private var columnsForSelectedRepo: [KanbanColumn] {
        (selectedRepo?.columns ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        NavigationStack {
            Group {
                if repos.isEmpty {
                    ContentUnavailableView(
                        "quick_add_no_repos_title",
                        systemImage: "tray",
                        description: Text("quick_add_no_repos_subtitle")
                    )
                } else {
                    formContent
                }
            }
            .navigationTitle("quick_add_task_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear {
                selectedRepo = repos.first { $0.isFavorite } ?? repos.first
                refreshColumns(for: selectedRepo)
            }
            .onChange(of: selectedRepo) { _, newRepo in
                refreshColumns(for: newRepo)
            }
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                isContentFocused = true
            }
        }
        .presentationDetents([.medium, .large])
        .frame(idealWidth: 480)
    }

    private var formContent: some View {
        Form {
            Section("task_section") {
                TextField("task_placeholder", text: $content, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($isContentFocused)
            }

            Section("quick_add_repo_section") {
                Picker("quick_add_repo_picker", selection: $selectedRepo) {
                    ForEach(repos) { repo in
                        HStack {
                            if repo.isFavorite {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                            }
                            Text(repo.name)
                        }
                        .tag(repo as ProjectRepo?)
                    }
                }
            }

            if !columnsForSelectedRepo.isEmpty {
                Section("column") {
                    Picker("column", selection: $selectedColumn) {
                        ForEach(columnsForSelectedRepo) { column in
                            HStack {
                                Circle()
                                    .fill(Color(hex: column.colorHex))
                                    .frame(width: 12, height: 12)
                                Text(column.name)
                            }
                            .tag(column as KanbanColumn?)
                        }
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("create") { createTask() }
                .disabled(
                    content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || selectedRepo == nil || selectedColumn == nil
                )
        }
    }

    // MARK: - Actions

    private func refreshColumns(for repo: ProjectRepo?) {
        guard let repo else {
            selectedColumn = nil
            return
        }
        if (repo.columns ?? []).isEmpty {
            let vm = KanbanViewModel(project: repo, modelContext: context)
            vm.initializeDefaultColumnsIfNeeded()
        }
        selectedColumn = (repo.columns ?? []).sorted { $0.orderIndex < $1.orderIndex }.first
    }

    private func createTask() {
        guard let repo = selectedRepo, let column = selectedColumn else { return }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let maxOrder = (column.tasks ?? []).map(\.orderIndex).max() ?? -1
        let task = TaskItem(
            content: trimmed,
            status: column.name.lowercased().replacingOccurrences(of: " ", with: "_"),
            column: column,
            project: repo,
            orderIndex: maxOrder + 1
        )
        context.insert(task)
        try? context.save()

        TaskIssueSyncService.shared.syncNewTaskInBackground(task, repo: repo, context: context)

        ToastManager.shared.show(
            String(format: String(localized: "quick_add_task_created %@"), repo.name),
            style: .success
        )
        dismiss()
    }
}
