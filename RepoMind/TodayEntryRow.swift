import SwiftData
import SwiftUI

/// Entry point to `TodayView`, shown above the repo list.
///
/// Carries its own counts so "is anything waiting for me?" is answered without opening anything —
/// that previously meant entering each repo in turn. Renders nothing when there is nothing to
/// report, so a quiet app stays quiet.
struct TodayEntryRow: View {
    @Query private var allIssues: [FeedbackIssue]
    @Query private var repos: [ProjectRepo]

    private let syncMonitor = CloudKitSyncMonitor.shared

    private var unreadCount: Int {
        allIssues.filter { !$0.isRead && !$0.isSnoozed && $0.state == "open" }.count
    }

    private var unpublishedCount: Int {
        repos.reduce(0) { $0 + ($1.tasks ?? []).filter(\.needsIssueSync).count }
    }

    private var hasWarning: Bool {
        syncMonitor.hasSyncProblem || repos.contains { $0.syncTasksDisabledReason != nil }
    }

    var isEmpty: Bool { unreadCount == 0 && unpublishedCount == 0 && !hasWarning }

    var body: some View {
        if !isEmpty {
            NavigationLink {
                TodayView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: hasWarning ? "exclamationmark.circle.fill" : "tray.full.fill")
                        .font(.title3)
                        .foregroundStyle(hasWarning ? .orange : .purple)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("today_title")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var summary: String {
        var parts: [String] = []
        if unreadCount > 0 {
            parts.append(String(format: String(localized: "today_summary_feedback %lld"), unreadCount))
        }
        if unpublishedCount > 0 {
            parts.append(String(format: String(localized: "today_summary_unpublished %lld"), unpublishedCount))
        }
        if hasWarning {
            parts.append(String(localized: "today_summary_warning"))
        }
        return parts.joined(separator: " · ")
    }
}
