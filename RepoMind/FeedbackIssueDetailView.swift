import SwiftData
import SwiftUI

struct FeedbackIssueDetailView: View {
    @Bindable var issue: FeedbackIssue
    let repo: ProjectRepo

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var columns: [KanbanColumn]

    @State private var commentText = ""
    @State private var isWorking = false
    @State private var actionError: String?
    @State private var showCloseConfirm = false
    @State private var showConvertSheet = false
    @State private var showSnoozeSheet = false
    @State private var lastFeedback: String?

    init(issue: FeedbackIssue, repo: ProjectRepo) {
        self.issue = issue
        self.repo = repo
        let projectID = repo.persistentModelID
        let filter = #Predicate<KanbanColumn> { $0.project?.persistentModelID == projectID }
        _columns = Query(filter: filter, sort: \KanbanColumn.orderIndex)
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(issue.title).font(.headline)
                    HStack(spacing: 8) {
                        SeverityBadge(severity: issue.severityEnum)
                        Text(issue.state)
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(issue.state == "open" ? Color.green.opacity(0.2) : Color.gray.opacity(0.2), in: Capsule())
                            .foregroundStyle(issue.state == "open" ? .green : .secondary)
                        Text(issue.createdAt, style: .date)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !issue.bodyText.isEmpty {
                        Text(issue.bodyText).font(.callout).foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                    if let columnName = issue.convertedTaskColumnName {
                        Label(String(format: String(localized: "feedback_converted_in %@"), columnName), systemImage: "rectangle.stack.fill")
                            .font(.caption)
                            .padding(.top, 4)
                            .foregroundStyle(.purple)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("feedback_actions_section") {
                Button {
                    if let url = URL(string: issue.htmlURL) { UIApplication.shared.open(url) }
                } label: { Label("feedback_open_in_github", systemImage: "arrow.up.right.square") }

                Button {
                    issue.isRead.toggle()
                    try? context.save()
                } label: { Label(issue.isRead ? "feedback_mark_unread" : "feedback_mark_read",
                                 systemImage: issue.isRead ? "envelope.badge" : "envelope.open") }

                Button {
                    showConvertSheet = true
                } label: { Label("feedback_convert_to_task", systemImage: "rectangle.stack.badge.plus") }

                Button {
                    showSnoozeSheet = true
                } label: { Label("feedback_snooze", systemImage: "moon.zzz") }

                if issue.state == "open" {
                    Button(role: .destructive) {
                        showCloseConfirm = true
                    } label: { Label("feedback_close_issue", systemImage: "xmark.circle") }
                } else {
                    Button {
                        Task { await runAction { try await reopen() } }
                    } label: { Label("feedback_reopen_issue", systemImage: "arrow.uturn.backward.circle") }
                }
            }

            Section("feedback_severity_section") {
                Picker("feedback_severity_picker", selection: Binding(
                    get: { issue.severityEnum },
                    set: { newValue in Task { await runAction { try await changeSeverity(to: newValue) } } }
                )) {
                    ForEach(FeedbackSeverity.allCases, id: \.self) { sev in
                        Text(sev.localized).tag(sev)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("feedback_comment_section") {
                TextField("feedback_comment_placeholder", text: $commentText, axis: .vertical)
                    .lineLimit(3...8)
                Button {
                    Task { await runAction { try await postComment() } }
                } label: {
                    Label("feedback_send_comment", systemImage: "paperplane")
                }
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            }

            if let lastFeedback {
                Section { Text(lastFeedback).font(.caption).foregroundStyle(.green) }
            }
        }
        .navigationTitle(Text("feedback_issue_number \(issue.issueNumber)"))
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("close") { dismiss() }
            }
        }
        .overlay {
            if isWorking { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)) }
        }
        .alert("feedback_close_confirm_title", isPresented: $showCloseConfirm) {
            Button("cancel_button", role: .cancel) {}
            Button("feedback_close_issue", role: .destructive) {
                Task { await runAction { try await close() } }
            }
        } message: { Text("feedback_close_confirm_message") }
        .alert("feedback_sync_error_title", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("ok") { actionError = nil }
        } message: { Text(actionError ?? "") }
        .sheet(isPresented: $showConvertSheet) { convertSheet }
        .sheet(isPresented: $showSnoozeSheet) { snoozeSheet }
        // Deliberately does NOT mark as read on appear. Opening something is not deciding anything
        // about it, and auto-reading made items vanish from Today before the developer had done
        // anything with them. It clears when they actually act on it — see `markHandled`.
    }

    // MARK: - Convert sheet

    private var convertSheet: some View {
        NavigationStack {
            List {
                ForEach(columns) { column in
                    Button {
                        convertToTask(in: column)
                        showConvertSheet = false
                    } label: {
                        HStack {
                            Circle().fill(Color(hex: column.colorHex)).frame(width: 12, height: 12)
                            Text(column.name)
                            Spacer()
                            Text("\(column.tasks?.count ?? 0)")
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
            .navigationTitle("feedback_convert_pick_column")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("cancel_button") { showConvertSheet = false } } }
        }
        .frame(idealWidth: 400, idealHeight: 500)
    }

    // MARK: - Snooze sheet

    private var snoozeSheet: some View {
        NavigationStack {
            List {
                Button { snooze(days: 1); showSnoozeSheet = false } label: { Text("feedback_snooze_1d") }
                Button { snooze(days: 3); showSnoozeSheet = false } label: { Text("feedback_snooze_3d") }
                Button { snooze(days: 7); showSnoozeSheet = false } label: { Text("feedback_snooze_7d") }
                Button { snooze(days: 30); showSnoozeSheet = false } label: { Text("feedback_snooze_30d") }
                if issue.snoozedUntil != nil {
                    Button(role: .destructive) {
                        issue.snoozedUntil = nil
                        try? context.save()
                        showSnoozeSheet = false
                    } label: { Text("feedback_snooze_clear") }
                }
            }
            .navigationTitle("feedback_snooze")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("cancel_button") { showSnoozeSheet = false } } }
        }
        .frame(idealWidth: 300, idealHeight: 380)
    }

    // MARK: - Actions

    /// Marks the item as dealt with. Called only from real decisions — converting it into a task,
    /// closing it, or snoozing it — never from merely looking at it.
    private func markHandled() {
        guard !issue.isRead else { return }
        issue.isRead = true
    }

    private func snooze(days: Int) {
        issue.snoozedUntil = Calendar.current.date(byAdding: .day, value: days, to: .now)
        markHandled()
        try? context.save()
    }

    private func convertToTask(in column: KanbanColumn) {
        let nextOrder = (column.tasks?.map(\.orderIndex).max() ?? -1) + 1
        let content = "\(issue.title)\n\n\(issue.htmlURL)"
        let task = TaskItem(content: content, column: column, project: repo, orderIndex: nextOrder)
        context.insert(task)
        issue.convertedTaskColumnName = column.name
        markHandled()
        try? context.save()
        lastFeedback = String(format: String(localized: "feedback_converted_in %@"), column.name)
    }

    private func runAction(_ block: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do { try await block() } catch { actionError = error.localizedDescription }
    }

    private func close() async throws {
        let token = try await token()
        try await FeedbackService.shared.closeIssue(issue, token: token, in: context)
        markHandled()
        try? context.save()
        lastFeedback = String(localized: "feedback_close_done")
    }

    private func reopen() async throws {
        let token = try await token()
        try await FeedbackService.shared.reopenIssue(issue, token: token, in: context)
        lastFeedback = String(localized: "feedback_reopen_done")
    }

    private func postComment() async throws {
        let token = try await token()
        try await FeedbackService.shared.addComment(to: issue, body: commentText, token: token)
        commentText = ""
        lastFeedback = String(localized: "feedback_comment_done")
    }

    private func changeSeverity(to severity: FeedbackSeverity) async throws {
        guard severity != issue.severityEnum else { return }
        let token = try await token()
        try await FeedbackService.shared.updateSeverity(issue, to: severity, token: token, in: context)
        lastFeedback = String(localized: "feedback_severity_done")
    }

    private func token() async throws -> String {
        guard let account = repo.account,
              let t = try await KeychainManager.shared.retrieveToken(for: account.tokenKey)
        else { throw FeedbackService.FeedbackError.noOwner }
        return t
    }
}

// MARK: - Severity Badge

private struct SeverityBadge: View {
    let severity: FeedbackSeverity

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(severity.localized).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(.white)
        .background(color, in: Capsule())
    }

    private var icon: String {
        switch severity {
        case .critical: return "exclamationmark.triangle.fill"
        case .minor: return "ant.fill"
        case .enhancement: return "sparkles"
        case .general: return "bubble.left.fill"
        }
    }

    private var color: Color {
        switch severity {
        case .critical: return .red
        case .minor: return .yellow
        case .enhancement: return .green
        case .general: return .blue
        }
    }
}

extension FeedbackSeverity {
    var localized: String {
        switch self {
        case .critical: return String(localized: "feedback_severity_critical")
        case .minor: return String(localized: "feedback_severity_minor")
        case .enhancement: return String(localized: "feedback_severity_enhancement")
        case .general: return String(localized: "feedback_severity_general")
        }
    }
}
