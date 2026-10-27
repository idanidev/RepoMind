import SwiftData
import SwiftUI

// MARK: - Digest lists

/// The list behind a number on the home digest: the tasks or repos it counted, grouped by
/// repo, each opening its board. Reads the models itself, like `TodayView`, and counts through
/// the same `HomeDigest` functions as the card, so the two always agree.
struct HomeDigestView: View {
    let kind: HomeDigestKind

    @Environment(\.openURL) private var openURL
    @Query(sort: \ProjectRepo.updatedAt, order: .reverse) private var repos: [ProjectRepo]
    @State private var activity = RepoActivityStore.shared

    private var live: [ProjectRepo] { repos.filter { !$0.isArchived } }

    var body: some View {
        Group {
            switch kind {
            case .abandoned:
                taskList(HomeDigest.abandonedTasks(in: live), showsAge: true)
            case .syncErrors:
                taskList(HomeDigest.syncErrorTasks(in: live), showsAge: false)
            case .unpublished:
                taskList(HomeDigest.unpublishedTasks(in: live), showsAge: false)
            case .failingBuilds:
                repoList(HomeDigest.failingRepos(in: live, activity: activity.activity(for:)), path: "actions")
            case .pullRequests:
                repoList(
                    HomeDigest.pullRequestRepos(in: live, activity: activity.activity(for:)).map { $0.repo },
                    path: "pulls")
            case .dormant:
                repoList(HomeDigest.dormantRepos(in: live, activity: activity.activity(for:)), path: nil)
            case .feedback:
                TodayView()
            }
        }
        .navigationTitle(title)
    }

    private var title: LocalizedStringKey {
        switch kind {
        case .abandoned: "home_digest_title_abandoned"
        case .syncErrors: "home_digest_title_sync_errors"
        case .unpublished: "today_unpublished_section"
        case .failingBuilds: "home_digest_title_builds"
        case .pullRequests: "home_digest_title_prs"
        case .dormant: "home_digest_title_dormant"
        case .feedback: "today_title"
        }
    }

    // MARK: Tasks

    private struct RepoGroup: Identifiable {
        let repo: ProjectRepo
        let tasks: [TaskItem]
        var id: PersistentIdentifier { repo.persistentModelID }
    }

    /// Tasks under their repo, repos in the order their first task appears.
    private func groups(_ tasks: [TaskItem]) -> [RepoGroup] {
        var order: [ProjectRepo] = []
        var byRepo: [PersistentIdentifier: [TaskItem]] = [:]
        for task in tasks {
            guard let repo = task.project else { continue }
            if byRepo[repo.persistentModelID] == nil { order.append(repo) }
            byRepo[repo.persistentModelID, default: []].append(task)
        }
        return order.map { RepoGroup(repo: $0, tasks: byRepo[$0.persistentModelID] ?? []) }
    }

    @ViewBuilder
    private func taskList(_ tasks: [TaskItem], showsAge: Bool) -> some View {
        let grouped = groups(tasks)
        if grouped.isEmpty {
            ContentUnavailableView("home_digest_empty", systemImage: "checkmark.circle")
        } else {
            List {
                if kind == .abandoned {
                    Section {
                        Text("home_digest_abandoned_footer")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(grouped) { group in
                    Section {
                        ForEach(group.tasks) { task in
                            taskRow(task, showsAge: showsAge)
                        }
                        NavigationLink(value: group.repo) {
                            Label("home_digest_open_board", systemImage: "rectangle.split.3x1")
                        }
                    } header: {
                        HStack {
                            Text(group.repo.name)
                            Spacer()
                            Text(group.tasks.count.formatted()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .macSidebarListStyle()
        }
    }

    private func taskRow(_ task: TaskItem, showsAge: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(task.content).lineLimit(3)
            HStack(spacing: 6) {
                if let column = task.column?.name {
                    Text(column)
                }
                if showsAge {
                    Text("home_digest_captured_ago \(task.createdAt.formatted(.relative(presentation: .named)))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let reason = task.lastSyncError {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: Repos

    @ViewBuilder
    private func repoList(_ list: [ProjectRepo], path: String?) -> some View {
        if list.isEmpty {
            ContentUnavailableView("home_digest_empty", systemImage: "checkmark.circle")
        } else {
            List {
                if kind == .dormant {
                    Section {
                        Text("home_digest_dormant_footer")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(list) { repo in
                    Section {
                        NavigationLink(value: repo) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.name).font(.subheadline.weight(.semibold))
                                Text(detail(for: repo))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let path, let url = URL(string: repo.htmlURL + "/" + path), !repo.htmlURL.isEmpty {
                            Button {
                                openURL(url)
                            } label: {
                                Label("home_open_on_github", systemImage: "arrow.up.right.square")
                            }
                        }
                    }
                }
            }
            .macSidebarListStyle()
        }
    }

    private func detail(for repo: ProjectRepo) -> String {
        var parts: [String] = []
        let facts = activity.activity(for: repo.repoID)
        if let count = facts?.openPullRequests, count > 0 {
            parts.append(String(format: String(localized: "home_digest_pr_count %lld"), count))
        }
        if facts?.isBuildFailing == true {
            parts.append(String(localized: "home_digest_build_failing"))
        }
        let pending = HomeDigest.pendingTasks(in: [repo]).count
        if pending > 0 {
            parts.append(String(format: String(localized: "home_stat_pending %lld"), pending))
        }
        if let pushed = facts?.pushedAt {
            let relative = pushed.formatted(.relative(presentation: .named))
            parts.append(String(format: String(localized: "home_digest_last_push %@"), relative))
        }
        return parts.joined(separator: " · ")
    }
}
