import SwiftData
import SwiftUI

// MARK: - Feedback View

struct FeedbackView: View {
    let repo: ProjectRepo

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var scopedIssues: [FeedbackIssue]

    @State private var isSyncing = false
    @State private var syncError: String?

    private let repoFullName: String

    init(repo: ProjectRepo) {
        self.repo = repo
        let fullName = repo.fullName
        self.repoFullName = fullName
        let predicate = #Predicate<FeedbackIssue> { $0.repoFullName == fullName }
        _scopedIssues = Query(filter: predicate, sort: \FeedbackIssue.createdAt, order: .reverse)
    }

    private var issues: [FeedbackIssue] {
        scopedIssues.filter { !$0.isSnoozed }
    }

    private var groupedIssues: [(FeedbackSeverity, [FeedbackIssue])] {
        let grouped = Dictionary(grouping: issues) { $0.severityEnum }
        return FeedbackSeverity.allCases.compactMap { sev in
            guard let arr = grouped[sev], !arr.isEmpty else { return nil }
            return (sev, arr.sorted { $0.createdAt > $1.createdAt })
        }
    }

    var body: some View {
        Group {
            if issues.isEmpty {
                emptyState
            } else {
                issueList
            }
        }
        .navigationTitle("feedback_title")
        .toolbar { syncButton }
        .task { await sync() }
        .alert("feedback_sync_error_title",
               isPresented: Binding(get: { syncError != nil }, set: { if !$0 { syncError = nil } })) {
            Button("ok") { syncError = nil }
        } message: {
            Text(syncError ?? "")
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView(
            "feedback_empty_title",
            systemImage: "tray",
            description: Text("feedback_empty_subtitle")
        )
    }

    private var issueList: some View {
        List {
            ForEach(groupedIssues, id: \.0) { severity, issues in
                Section {
                    ForEach(issues) { issue in
                        NavigationLink {
                            FeedbackIssueDetailView(issue: issue, repo: repo)
                        } label: {
                            FeedbackRow(issue: issue)
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: severity.iconName)
                            .foregroundStyle(severity.tintColor)
                        Text(severity.localizedTitle)
                        Spacer()
                        Text("\(issues.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await sync() }
    }

    @ToolbarContentBuilder
    private var syncButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("close") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await sync() }
            } label: {
                if isSyncing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(isSyncing)
        }
    }

    // MARK: - Actions

    private func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        guard let account = repo.account else { return }
        let token: String? = try? await KeychainManager.shared.retrieveToken(for: account.tokenKey)
        guard let token else { return }

        do {
            let new = try await FeedbackService.shared.sync(repo: repo, token: token, into: context)
            await FeedbackNotificationManager.shared.notify(for: new)
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func open(_ issue: FeedbackIssue) {
        if !issue.isRead {
            issue.isRead = true
            try? context.save()
        }
        if let url = URL(string: issue.htmlURL) {
            #if canImport(UIKit)
                UIApplication.shared.open(url)
            #endif
        }
    }
}

// MARK: - Row

private struct FeedbackRow: View {
    let issue: FeedbackIssue

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(issue.isRead ? Color.clear : .blue)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(issue.title)
                    .font(.subheadline.weight(issue.isRead ? .regular : .semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(issue.createdAt, style: .date)
                    Text("•")
                    Text(issue.source.capitalized)
                    if let rating = issue.rating {
                        Text("•")
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                            Text("\(rating)")
                        }
                    }
                    Text("•")
                    Text(issue.state)
                        .foregroundStyle(issue.state == "open" ? .green : .secondary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let until = issue.snoozedUntil, until > .now {
                Image(systemName: "moon.zzz.fill")
                    .font(.caption)
                    .foregroundStyle(.indigo)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Severity UI

private extension FeedbackSeverity {
    var iconName: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .minor: return "ant.fill"
        case .enhancement: return "sparkles"
        case .general: return "bubble.left.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .critical: return .red
        case .minor: return .yellow
        case .enhancement: return .green
        case .general: return .blue
        }
    }

    var localizedTitle: LocalizedStringKey {
        switch self {
        case .critical: return "feedback_severity_critical"
        case .minor: return "feedback_severity_minor"
        case .enhancement: return "feedback_severity_enhancement"
        case .general: return "feedback_severity_general"
        }
    }
}

// MARK: - Unread Badge Helper

extension ProjectRepo {
    /// Compute unread feedback count from a pre-fetched array (avoids fetching from inside a view).
    func unreadFeedbackCount(in issues: [FeedbackIssue]) -> Int {
        let target = fullName
        return issues.filter { $0.repoFullName == target && !$0.isRead }.count
    }
}
