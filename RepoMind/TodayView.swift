import SwiftData
import SwiftUI

/// Everything that wants attention, across every repo, on one screen.
///
/// The signals already existed — unread feedback, tasks that never reached GitHub, repos whose
/// sync switched itself off — but each was buried inside its own repo, so answering "what should
/// I do now?" meant opening every board in turn.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var allIssues: [FeedbackIssue]
    @Query(sort: \ProjectRepo.updatedAt, order: .reverse) private var repos: [ProjectRepo]

    @State private var isRetrying = false

    private let syncMonitor = CloudKitSyncMonitor.shared

    /// Repo lookup keyed by `owner/name`, so a feedback row can name the project it belongs to.
    private var reposByFullName: [String: ProjectRepo] {
        Dictionary(repos.map { ($0.fullName, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var unreadFeedback: [FeedbackIssue] {
        let rank: [FeedbackSeverity: Int] = [.critical: 0, .minor: 1, .enhancement: 2, .general: 3]
        return allIssues
            .filter { !$0.isRead && !$0.isSnoozed && $0.state == "open" }
            .sorted { lhs, rhs in
                let l = rank[lhs.severityEnum] ?? 3
                let r = rank[rhs.severityEnum] ?? 3
                return l == r ? lhs.createdAt > rhs.createdAt : l < r
            }
    }

    private var unpublishedTasks: [TaskItem] {
        repos.flatMap { $0.tasks ?? [] }.filter(\.needsIssueSync)
    }

    /// Retries every repo that has something stuck, without making the user visit each board.
    private func retryUnpublished() async {
        isRetrying = true
        defer { isRetrying = false }

        // Reattach first: a task with no column cannot be published at all, so retrying the
        // network call before fixing that would just reproduce the same error.
        OrphanTaskRepair.run(context: context)

        // Every synced repo, not only the ones with something stuck: an agent may have closed
        // issues in a repo that had nothing pending, and those tasks are still sitting in To-Do.
        var moved = 0
        for repo in repos where repo.syncTasksToGitHub {
            guard let account = repo.account,
                  let token = try? await KeychainManager.shared.retrieveToken(for: account.tokenKey)
            else { continue }

            if (repo.tasks ?? []).contains(where: \.needsIssueSync) {
                await TaskIssueSyncService.shared.reconcile(repo: repo, context: context, token: token)
            }
            moved += await TaskIssueSyncService.shared.importClosedIssues(
                repo: repo, context: context, token: token)
        }

        if moved > 0 {
            ToastManager.shared.show(
                String(format: String(localized: "tasks_completed_by_agent %lld"), moved),
                style: .success)
        }
    }

    private var reposWithBrokenSync: [ProjectRepo] {
        repos.filter { $0.syncTasksDisabledReason != nil }
    }

    private var hasNothingToShow: Bool {
        unreadFeedback.isEmpty && unpublishedTasks.isEmpty
            && reposWithBrokenSync.isEmpty && !syncMonitor.hasSyncProblem
    }

    var body: some View {
        Group {
            if hasNothingToShow {
                ContentUnavailableView(
                    "today_all_clear_title",
                    systemImage: "checkmark.circle",
                    description: Text("today_all_clear_subtitle")
                )
            } else {
                List {
                    warningsSection
                    feedbackSection
                    unpublishedSection
                }
                .macSidebarListStyle()
            }
        }
        .navigationTitle("today_title")
    }

    // MARK: - Sections

    @ViewBuilder
    private var warningsSection: some View {
        if syncMonitor.hasSyncProblem || !reposWithBrokenSync.isEmpty {
            Section("today_warnings_section") {
                if syncMonitor.hasSyncProblem {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("icloud_sync_problem_title")
                            // The detail first: the top-level message for a partial failure is
                            // "the operation could not be completed", which says nothing.
                            if let detail = syncMonitor.lastErrorDetail {
                                Text(detail).font(.caption)
                            } else if let message = syncMonitor.lastErrorMessage {
                                Text(message).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.icloud").foregroundStyle(.orange)
                    }
                }

                ForEach(reposWithBrokenSync) { repo in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(repo.name)
                            Text("today_sync_disabled").font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var feedbackSection: some View {
        if !unreadFeedback.isEmpty {
            Section {
                ForEach(unreadFeedback.prefix(10)) { issue in
                    NavigationLink {
                        if let repo = reposByFullName[issue.repoFullName] {
                            FeedbackIssueDetailView(issue: issue, repo: repo)
                        }
                    } label: {
                        FeedbackRowCompact(
                            issue: issue,
                            repoName: reposByFullName[issue.repoFullName]?.name ?? issue.repoFullName
                        )
                    }
                    .disabled(reposByFullName[issue.repoFullName] == nil)
                }
            } header: {
                HStack {
                    Text("today_feedback_section")
                    Spacer()
                    Text("\(unreadFeedback.count)").foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var unpublishedSection: some View {
        if !unpublishedTasks.isEmpty {
            Section {
                ForEach(unpublishedTasks.prefix(10)) { task in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.content).lineLimit(2)
                        if let repoName = task.project?.name {
                            Text(repoName).font(.caption).foregroundStyle(.secondary)
                        }
                        // The reason it is stuck. Without this the list said "not published" and
                        // left you guessing between offline, expired token and no permission.
                        if let reason = task.lastSyncError {
                            Label(reason, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // Retrying used to require opening each affected board, since that was the only
                // place `reconcile` ran.
                Button {
                    Task { await retryUnpublished() }
                } label: {
                    Label("today_unpublished_retry", systemImage: "arrow.clockwise")
                }
                .disabled(isRetrying)
            } header: {
                Text("today_unpublished_section")
            } footer: {
                Text("today_unpublished_footer")
            }
        }
    }
}

// MARK: - Compact feedback row

private struct FeedbackRowCompact: View {
    let issue: FeedbackIssue
    let repoName: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.caption)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title).font(.subheadline).lineLimit(2)
                Text(repoName).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var icon: String {
        switch issue.severityEnum {
        case .critical: "exclamationmark.triangle.fill"
        case .minor: "ant.fill"
        case .enhancement: "sparkles"
        case .general: "bubble.left.fill"
        }
    }

    private var tint: Color {
        switch issue.severityEnum {
        case .critical: .red
        case .minor: .yellow
        case .enhancement: .green
        case .general: .blue
        }
    }
}
