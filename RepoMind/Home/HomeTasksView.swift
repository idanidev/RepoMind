import Foundation
import SwiftUI

// MARK: - Rows

enum HomeTaskState: Hashable {
    case pending
    case done
    case idea
}

/// One task as the Tasks tab draws it, flattened like a card: nothing here touches the models.
struct HomeTaskRow: Hashable, Identifiable {
    let id: UUID
    let title: String
    let repoName: String
    let repoCardID: String
    let columnName: String?
    let createdAt: Date
    let issueNumber: Int?
    let needsIssueSync: Bool
    let state: HomeTaskState
}

enum HomeTaskFilter: String, CaseIterable, Identifiable, HomeChipOption {
    case pending
    case recent
    case done
    case ideas

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .pending: "home_tasks_filter_pending"
        case .recent: "home_tasks_filter_recent"
        case .done: "home_tasks_filter_done"
        case .ideas: "home_tasks_filter_ideas"
        }
    }

    /// Recent means captured in the last week, whatever its state.
    func apply(to rows: [HomeTaskRow], now: Date = .now) -> [HomeTaskRow] {
        switch self {
        case .pending: rows.filter { $0.state == .pending }
        case .recent: rows.filter { now.timeIntervalSince($0.createdAt) <= HomeDigest.capturedWindow }
        case .done: rows.filter { $0.state == .done }
        case .ideas: rows.filter { $0.state == .idea }
        }
    }
}

extension HomeTaskRow {
    /// Chip and search applied, then grouped by repo: the repo with most rows first, newest
    /// rows first inside it.
    static func groups(
        _ rows: [HomeTaskRow], filter: HomeTaskFilter, query: String, now: Date = .now
    ) -> [HomeTaskGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var matching = filter.apply(to: rows, now: now)
        if !trimmed.isEmpty {
            matching = matching.filter {
                $0.title.localizedStandardContains(trimmed) || $0.repoName.localizedStandardContains(trimmed)
            }
        }
        var order: [String] = []
        var byRepo: [String: [HomeTaskRow]] = [:]
        for row in matching.sorted(by: { $0.createdAt > $1.createdAt }) {
            if byRepo[row.repoCardID] == nil { order.append(row.repoCardID) }
            byRepo[row.repoCardID, default: []].append(row)
        }
        return order
            .compactMap { id -> HomeTaskGroup? in
                guard let rows = byRepo[id], let first = rows.first else { return nil }
                return HomeTaskGroup(id: id, repoName: first.repoName, rows: rows)
            }
            .sorted { $0.rows.count != $1.rows.count ? $0.rows.count > $1.rows.count : $0.repoName < $1.repoName }
    }
}

struct HomeTaskGroup: Hashable, Identifiable {
    /// The repo's `homeCardID`.
    let id: String
    let repoName: String
    let rows: [HomeTaskRow]
}

// MARK: - Actions

struct HomeTasksActions {
    var openRepo: (String) -> Void = { _ in }
    var openToday: () -> Void = {}
    var refresh: () async -> Void = {}
}

// MARK: - Tasks tab

/// Every task of every repo on one screen, by state, grouped by repo. The board is one repo;
/// this is the whole backlog. A row opens the repo's board; what needs attention (unread
/// reports, tasks that never reached GitHub) stays one tap away at the top.
struct HomeTasksView: View {
    let rows: [HomeTaskRow]
    var attention = 0
    var searchText = ""
    var actions = HomeTasksActions()

    @State private var filter: HomeTaskFilter = .pending

    private var groups: [HomeTaskGroup] { HomeTaskRow.groups(rows, filter: filter, query: searchText) }

    private var pending: Int { rows.filter { $0.state == .pending }.count }
    private var done: Int { rows.filter { $0.state == .done }.count }
    private var ideas: Int { rows.filter { $0.state == .idea }.count }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                header
                if attention > 0 {
                    attentionRow
                }
                let groups = self.groups
                if groups.isEmpty {
                    emptyState
                } else {
                    ForEach(groups) { group in
                        groupCard(group)
                    }
                }
            }
            .padding(.horizontal, HomeTheme.gutter)
            .padding(.top, 6)
            .padding(.bottom, 12)
            .animation(.smooth(duration: 0.25), value: filter)
        }
        .refreshable { await actions.refresh() }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("home_tasks_title")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(HomeTheme.textPrimary)
            Text(String(format: String(localized: "home_tasks_summary %lld %lld %lld"), pending, done, ideas))
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(HomeTheme.textSecondary)
            HomeFilterChips(selection: $filter)
        }
        .padding(.bottom, 2)
    }

    private var attentionRow: some View {
        Button(action: actions.openToday) {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(HomeTheme.warning)
                Text(String(format: String(localized: "home_tasks_attention %lld"), attention))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(HomeTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(HomeTheme.textSecondary)
            }
            .padding(HomeTheme.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: HomeTheme.cardRadius, style: .continuous)
                    .fill(HomeTheme.warning.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: HomeTheme.cardRadius, style: .continuous)
                    .strokeBorder(HomeTheme.warning.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(HomeCardButtonStyle())
    }

    private func groupCard(_ group: HomeTaskGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                actions.openRepo(group.id)
            } label: {
                HStack {
                    Text(group.repoName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeTheme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(group.rows.count.formatted())
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(HomeTheme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(HomeTheme.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ForEach(group.rows) { row in
                taskRow(row, repoCardID: group.id)
            }
        }
        .padding(HomeTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeDashboardCardBackground())
    }

    private func taskRow(_ row: HomeTaskRow, repoCardID: String) -> some View {
        Button {
            actions.openRepo(repoCardID)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: symbol(for: row.state))
                    .font(.caption)
                    .foregroundStyle(tint(for: row.state))
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(.footnote)
                        .foregroundStyle(HomeTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(meta(for: row))
                        .font(.caption2)
                        .foregroundStyle(HomeTheme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func meta(for row: HomeTaskRow) -> String {
        var parts: [String] = []
        if let column = row.columnName { parts.append(column) }
        parts.append(row.createdAt.formatted(.relative(presentation: .named)))
        if let issue = row.issueNumber { parts.append("#\(issue)") }
        if row.needsIssueSync { parts.append(String(localized: "home_tasks_unpublished_badge")) }
        return parts.joined(separator: " · ")
    }

    private func symbol(for state: HomeTaskState) -> String {
        switch state {
        case .pending: "circle"
        case .done: "checkmark.circle.fill"
        case .idea: "lightbulb"
        }
    }

    private func tint(for state: HomeTaskState) -> Color {
        switch state {
        case .pending: HomeTheme.textSecondary
        case .done: HomeTheme.success
        case .idea: HomeTheme.warning
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            if searchText.isEmpty {
                Label("home_tasks_empty", systemImage: "checklist")
            } else {
                Label("home_tasks_empty_search", systemImage: "magnifyingglass")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// MARK: - From the models

extension HomeTaskRow {
    /// Every task with a column, as the board counts them, newest first.
    static func rows(in repos: [ProjectRepo]) -> [HomeTaskRow] {
        repos.flatMap { repo -> [HomeTaskRow] in
            let doneID = repo.doneColumn?.id
            return (repo.tasks ?? []).compactMap { task -> HomeTaskRow? in
                guard let column = task.column else { return nil }
                let state: HomeTaskState = repo.isIdea(task) ? .idea : (column.id == doneID ? .done : .pending)
                return HomeTaskRow(
                    id: task.id, title: task.content, repoName: repo.name, repoCardID: repo.homeCardID,
                    columnName: column.name, createdAt: task.createdAt, issueNumber: task.issueNumber,
                    needsIssueSync: task.needsIssueSync, state: state)
            }
        }
        .sorted { $0.createdAt > $1.createdAt }
    }
}

#Preview("Tasks") {
    HomeTasksView(rows: HomeMockData.taskRows, attention: 3)
        .background(HomeTheme.background)
        .preferredColorScheme(.dark)
}
