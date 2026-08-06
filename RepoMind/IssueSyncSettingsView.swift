import SwiftData
import SwiftUI

/// One place to decide which repositories mirror their tasks as GitHub Issues.
///
/// The per-repo toggle already existed, but only inside each board's settings sheet — so answering
/// "which of my repos are actually publishing?" meant opening every board in turn, and there was no
/// way to turn the whole thing on or off at once.
struct IssueSyncSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ProjectRepo.name) private var allRepos: [ProjectRepo]
    @AppStorage("isDemoMode") private var isDemoMode = false

    @State private var pendingBulkEnable = false
    @State private var isWorking = false

    /// Local projects have no GitHub side, and a repo with no account has no token to publish with.
    private var syncableRepos: [ProjectRepo] {
        allRepos.filter { !$0.isLocal && $0.account != nil }
    }

    /// How many issues a "turn everything on" would create right now.
    private var unpublishedTaskCount: Int {
        syncableRepos
            .filter { !$0.syncTasksToGitHub }
            .reduce(0) { $0 + ($1.tasks ?? []).filter { $0.issueNumber == nil }.count }
    }

    var body: some View {
        List {
            if syncableRepos.isEmpty {
                ContentUnavailableView(
                    "issue_sync_no_repos_title",
                    systemImage: "arrow.trianglehead.2.clockwise",
                    description: Text("issue_sync_no_repos_message")
                )
            } else {
                Section {
                    Button("issue_sync_enable_all") { pendingBulkEnable = true }
                        .disabled(isWorking || syncableRepos.allSatisfy(\.syncTasksToGitHub))
                    Button("issue_sync_disable_all", role: .destructive) { disableAll() }
                        .disabled(isWorking || syncableRepos.allSatisfy { !$0.syncTasksToGitHub })
                } footer: {
                    Text("issue_sync_settings_footer")
                }

                Section("issue_sync_per_repo_section") {
                    ForEach(syncableRepos) { repo in
                        RepoSyncToggleRow(repo: repo, isWorking: $isWorking)
                    }
                }
            }
        }
        .navigationTitle("issue_sync_settings_title")
        #if !targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .disabled(isDemoMode)
        .alert("issue_sync_confirm_enable_all_title", isPresented: $pendingBulkEnable) {
            Button("cancel_button", role: .cancel) {}
            Button("issue_sync_confirm_enable_all_button") { enableAll() }
        } message: {
            // Publishing cannot be undone from here — say how many issues it will create first.
            Text(String(format: String(localized: "issue_sync_confirm_enable_all %lld"), unpublishedTaskCount))
        }
    }

    private func enableAll() {
        let targets = syncableRepos.filter { !$0.syncTasksToGitHub }
        isWorking = true
        Task {
            for repo in targets {
                await IssueSyncActivation.enable(repo: repo, context: context)
            }
            isWorking = false
            ToastManager.shared.show(String(localized: "issue_sync_enabled_toast"), style: .success)
        }
    }

    /// Only flips the local flag. Issues already on GitHub are left alone — deleting or closing
    /// them behind the user's back is not what "stop syncing" means.
    private func disableAll() {
        for repo in syncableRepos where repo.syncTasksToGitHub {
            repo.syncTasksToGitHub = false
        }
        try? context.save()
        ToastManager.shared.show(String(localized: "issue_sync_disabled_toast"), style: .info)
    }
}

// MARK: - Row

private struct RepoSyncToggleRow: View {
    @Bindable var repo: ProjectRepo
    @Binding var isWorking: Bool

    @Environment(\.modelContext) private var context
    @State private var pendingEnable = false

    private var unpublishedCount: Int {
        (repo.tasks ?? []).filter { $0.issueNumber == nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: binding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.name)
                    Text(repo.fullName)
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
            }
            if let reason = repo.syncTasksDisabledReason, !repo.syncTasksToGitHub {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .disabled(isWorking)
        .alert("issue_sync_confirm_enable_title", isPresented: $pendingEnable) {
            Button("cancel_button", role: .cancel) {}
            Button("issue_sync_confirm_enable_all_button") {
                Task { await IssueSyncActivation.enable(repo: repo, context: context) }
            }
        } message: {
            Text(
                String(
                    format: String(localized: "issue_sync_confirm_enable %lld %@"),
                    unpublishedCount, repo.fullName))
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { repo.syncTasksToGitHub },
            set: { newValue in
                guard newValue else {
                    repo.syncTasksToGitHub = false
                    try? context.save()
                    return
                }
                if unpublishedCount > 0 {
                    pendingEnable = true  // confirm before creating issues
                } else {
                    Task { await IssueSyncActivation.enable(repo: repo, context: context) }
                }
            }
        )
    }
}

// MARK: - Activation

/// Turning sync on for a repo, in one place.
///
/// The board's own settings sheet grew this sequence first; it lives here so the global screen
/// cannot drift into a slightly different version of it — a repo enabled from Settings has to end
/// up in exactly the same state as one enabled from its board.
enum IssueSyncActivation {
    @MainActor
    static func enable(repo: ProjectRepo, context: ModelContext) async {
        repo.syncTasksToGitHub = true
        repo.syncTasksDisabledReason = nil

        guard let account = repo.account,
              let token = try? await KeychainManager.shared.retrieveToken(for: account.tokenKey)
        else {
            try? context.save()
            return
        }

        let columns = repo.columns ?? []
        await TaskIssueSyncService.shared.ensureLabels(repo: repo, columns: columns, token: token)
        for task in repo.tasks ?? [] where task.issueNumber == nil {
            task.needsIssueSync = true
        }
        try? context.save()
        await TaskIssueSyncService.shared.reconcile(repo: repo, context: context, token: token)
    }
}
