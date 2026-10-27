import Foundation
import SwiftData

// MARK: - Digest

/// What the user should know across every repo before opening any of them.
///
/// The cards say what each repo has; this says what the whole account has: tasks captured
/// long ago and still not done, builds in the red, pull requests waiting, repos with work
/// piling up and no pushes, and the headline of every app with statistics connected. Every
/// number is actionable: tapping it opens the list behind it.
///
/// Value-typed and model-free, like `HomeRepoCardData`: the home renders it, previews mock it,
/// and `HomeLiveView` builds it from the models through the extension below.
struct HomeDigest: Hashable {
    /// Pending for longer than `abandonedAfter`.
    var abandoned = 0
    /// Marked for GitHub and never published, ideas excluded.
    var unpublished = 0
    /// Whose last publish attempt failed with a reason.
    var syncErrors = 0
    /// Repos whose default branch is red on CI.
    var failingBuilds = 0
    /// Open pull requests across every repo GitHub answered for.
    var pullRequests = 0
    var unreadFeedback = 0
    /// Repos with pending tasks and no push in `dormantAfter`.
    var dormantRepos = 0
    /// Tasks captured in the last `capturedWindow`.
    var capturedThisWeek = 0
    var apps: [HomeDigestApp] = []

    /// Nothing to act on and no app to read: the card stays off the home.
    var isQuiet: Bool {
        abandoned == 0 && unpublished == 0 && syncErrors == 0 && failingBuilds == 0
            && pullRequests == 0 && unreadFeedback == 0 && dormantRepos == 0 && apps.isEmpty
    }

    static let abandonedAfter: TimeInterval = 14 * 24 * 60 * 60
    static let dormantAfter: TimeInterval = 30 * 24 * 60 * 60
    static let capturedWindow: TimeInterval = 7 * 24 * 60 * 60
}

/// One app with statistics connected: its primary number, the change, and what broke lately.
struct HomeDigestApp: Hashable, Identifiable {
    let repoID: Int
    let name: String
    /// "31 Activas 7 días": the primary headline, value and label.
    let headline: String
    /// Change of the primary headline against the previous period, in parts per one.
    let change: Double?
    let crashes: Int
    let reports: Int

    var id: Int { repoID }
}

/// Which list a digest number opens.
enum HomeDigestKind: Hashable {
    case abandoned
    case unpublished
    case syncErrors
    case failingBuilds
    case pullRequests
    case dormant
    case feedback
}

// MARK: - From the models

extension HomeDigest {
    /// Counts the same items the detail lists show, through the same functions, so a number on
    /// the home never disagrees with the screen it opens.
    init(
        repos: [ProjectRepo],
        unreadFeedback: Int,
        activity: (Int) -> RepoActivity?,
        stats: (Int) -> RepoStats?,
        now: Date = .now
    ) {
        let live = repos.filter { !$0.isArchived }
        self.init(
            abandoned: Self.abandonedTasks(in: live, now: now).count,
            unpublished: Self.unpublishedTasks(in: live).count,
            syncErrors: Self.syncErrorTasks(in: live).count,
            failingBuilds: Self.failingRepos(in: live, activity: activity).count,
            pullRequests: Self.pullRequestRepos(in: live, activity: activity).reduce(0) { $0 + $1.count },
            unreadFeedback: unreadFeedback,
            dormantRepos: Self.dormantRepos(in: live, activity: activity, now: now).count,
            capturedThisWeek: Self.capturedTasks(in: live, now: now).count,
            apps: live.compactMap { repo in
                stats(repo.repoID).flatMap { HomeDigestApp(repo: repo, stats: $0) }
            }
        )
    }

    /// Work, not ideas: tasks in a column that is neither the done one nor the idea one.
    static func pendingTasks(in repos: [ProjectRepo]) -> [TaskItem] {
        repos.flatMap { repo -> [TaskItem] in
            let doneID = repo.doneColumn?.id
            return (repo.tasks ?? []).filter { task in
                guard let column = task.column, column.id != doneID else { return false }
                return !repo.isIdea(task)
            }
        }
    }

    /// Captured more than `abandonedAfter` ago and still pending, oldest first. The capture date
    /// is the only date a task has: moving it between columns leaves no trace, so a task that
    /// was picked up yesterday after two idle weeks still counts. Better that than silence.
    static func abandonedTasks(in repos: [ProjectRepo], now: Date = .now) -> [TaskItem] {
        pendingTasks(in: repos)
            .filter { now.timeIntervalSince($0.createdAt) > abandonedAfter }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func unpublishedTasks(in repos: [ProjectRepo]) -> [TaskItem] {
        repos.flatMap { repo in (repo.tasks ?? []).filter { $0.needsIssueSync && !repo.isIdea($0) } }
    }

    static func syncErrorTasks(in repos: [ProjectRepo]) -> [TaskItem] {
        repos.flatMap { repo in
            (repo.tasks ?? []).filter { $0.lastSyncError != nil && !repo.isIdea($0) }
        }
    }

    static func capturedTasks(in repos: [ProjectRepo], now: Date = .now) -> [TaskItem] {
        repos.flatMap { repo in (repo.tasks ?? []).filter { now.timeIntervalSince($0.createdAt) <= capturedWindow } }
    }

    static func failingRepos(in repos: [ProjectRepo], activity: (Int) -> RepoActivity?) -> [ProjectRepo] {
        repos.filter { activity($0.repoID)?.isBuildFailing == true }
    }

    static func pullRequestRepos(
        in repos: [ProjectRepo], activity: (Int) -> RepoActivity?
    ) -> [(repo: ProjectRepo, count: Int)] {
        repos.compactMap { repo in
            guard let count = activity(repo.repoID)?.openPullRequests, count > 0 else { return nil }
            return (repo: repo, count: count)
        }
        .sorted { $0.count > $1.count }
    }

    /// Work waiting on a repo nobody has pushed to in `dormantAfter`. Only repos GitHub has
    /// answered for: without a push date there is nothing to judge.
    static func dormantRepos(
        in repos: [ProjectRepo], activity: (Int) -> RepoActivity?, now: Date = .now
    ) -> [ProjectRepo] {
        repos.filter { repo in
            guard !repo.isLocal, let pushed = activity(repo.repoID)?.pushedAt,
                  now.timeIntervalSince(pushed) > dormantAfter
            else { return false }
            return !pendingTasks(in: [repo]).isEmpty
        }
    }
}

extension HomeDigestApp {
    /// `nil` when the stats carry no headline at all: a row with nothing to say is noise.
    init?(repo: ProjectRepo, stats: RepoStats) {
        guard let headline = stats.primaryHeadline, let value = headline.value else { return nil }
        self.init(
            repoID: repo.repoID,
            name: repo.name,
            headline: value.formatted() + " " + headline.label,
            change: RepoStats.change(current: value, previous: headline.previous),
            crashes: stats.issues.filter(\.isCrash).count,
            reports: stats.issues.filter { !$0.isCrash }.count
        )
    }
}
