import Foundation
import SwiftData

// MARK: - Dashboard data

/// Everything the start screen draws, flattened and value-typed, like `HomeRepoCardData`.
///
/// The start screen is the answer to "how are things?" before opening any repo: what the day
/// and the week captured, what needs a hand (the digest), the rhythm of the last two weeks,
/// the latest captures, where work piles up, what GitHub knows, how every connected app is
/// doing, and the health of the account and its syncs. `HomeLiveView` builds it from the
/// models through the extension below; previews mock it.
struct HomeDashboardData: Hashable {
    var date = Date.now
    var accountNames: [String] = []
    var isPro = false
    var digest = HomeDigest()
    var tasks = HomeTaskTotals()
    /// Captures per day over the last `historyDays`, oldest first.
    var captureHistory: [HomeDayCount] = []
    /// Newest first.
    var recent: [HomeRecentTask] = []
    /// Most pending first.
    var busiest: [HomeRepoLoad] = []
    var github = HomeGitHubSummary()
    var apps: [HomeAppSummary] = []
    /// Most repos first.
    var languages: [HomeLanguageShare] = []
    var sync = HomeSyncStatus()
    var repos = HomeRepoCounts()

    static let historyDays = 14
    static let recentLimit = 8
    static let busiestLimit = 5
}

struct HomeTaskTotals: Hashable {
    var total = 0
    var pending = 0
    var done = 0
    var ideas = 0
    var capturedToday = 0
    var capturedWeek = 0

    /// Done over done plus pending: ideas are not work, so they do not count against it.
    var doneRatio: Double {
        let work = done + pending
        return work == 0 ? 0 : Double(done) / Double(work)
    }
}

struct HomeDayCount: Hashable, Identifiable {
    let date: Date
    let count: Int

    var id: Date { date }
}

struct HomeRecentTask: Hashable, Identifiable {
    let id: UUID
    let title: String
    let repoName: String
    let repoCardID: String
    let createdAt: Date
    let isDone: Bool
}

struct HomeRepoLoad: Hashable, Identifiable {
    /// The repo's `homeCardID`.
    let id: String
    let name: String
    let pending: Int
    let total: Int

    var ratio: Double { total == 0 ? 0 : Double(pending) / Double(total) }
}

/// What GitHub said about the repos it was asked about. All zero until the first refresh.
struct HomeGitHubSummary: Hashable {
    /// Repos the activity cache knows about. Zero means GitHub has not been asked yet.
    var known = 0
    var pushedToday = 0
    var pushedWeek = 0
    var openPullRequests = 0
    var failing: [String] = []
    /// Open Dependabot alerts across the repos the token can see them for.
    var securityAlerts = 0
    var privateRepos = 0
    var publicRepos = 0
    /// Newest first.
    var recentPushes: [HomeRepoPush] = []
    var releases: [HomeRepoRelease] = []
}

struct HomeRepoPush: Hashable, Identifiable {
    let id: String
    let name: String
    let pushedAt: Date
}

struct HomeRepoRelease: Hashable, Identifiable {
    let id: String
    let name: String
    let tag: String
}

/// One connected app: the digest row plus what makes a card worth the space.
struct HomeAppSummary: Hashable, Identifiable {
    let app: HomeDigestApp
    /// Headlines other than the primary one, with a value, at most four.
    let headlines: [HomeHeadlineValue]
    /// The first daily series, as values, for a sparkline.
    let sparkline: [Int]
    let periodDays: Int

    var id: Int { app.repoID }
}

struct HomeHeadlineValue: Hashable, Identifiable {
    let id: String
    let label: String
    let value: Int
}

struct HomeLanguageShare: Hashable, Identifiable {
    let id: String
    let count: Int

    var name: String { id }
}

struct HomeSyncStatus: Hashable {
    /// The iCloud detail when sync is failing, nil when it is fine.
    var iCloudProblem: String?
    var iCloudLastSuccess: Date?
    var lastGitHubSync: Date?
    var activityRefreshedAt: Date?
}

struct HomeRepoCounts: Hashable {
    var total = 0
    var favorites = 0
    var archived = 0
    var local = 0
    var folders = 0
    var accounts = 0
}

// MARK: - From the models

extension HomeDashboardData {
    init(
        repos: [ProjectRepo],
        accounts: [GitHubAccount],
        folders: Int,
        unreadFeedback: Int,
        activity: (Int) -> RepoActivity?,
        stats: (Int) -> RepoStats?,
        sync: HomeSyncStatus,
        isPro: Bool,
        now: Date = .now
    ) {
        let live = repos.filter { !$0.isArchived }
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)

        self.init(
            date: now,
            accountNames: accounts.map(\.username),
            isPro: isPro,
            digest: HomeDigest(
                repos: repos, unreadFeedback: unreadFeedback, activity: activity, stats: stats, now: now),
            tasks: Self.totals(in: live, startOfToday: startOfToday, now: now),
            captureHistory: Self.history(in: live, startOfToday: startOfToday, calendar: calendar),
            recent: Self.recent(in: live),
            busiest: Self.busiest(in: live),
            github: Self.github(in: live, activity: activity, now: now),
            apps: live.compactMap { repo in stats(repo.repoID).flatMap { HomeAppSummary(repo: repo, stats: $0) } },
            languages: Self.languages(in: live),
            sync: sync,
            repos: HomeRepoCounts(
                total: live.count,
                favorites: live.filter(\.isFavorite).count,
                archived: repos.count - live.count,
                local: live.filter(\.isLocal).count,
                folders: folders,
                accounts: accounts.count)
        )
    }

    /// A task is work, done, or an idea, exactly as the board counts it.
    private enum Shape { case pending, done, idea, orphan }

    private static func shape(of task: TaskItem, in repo: ProjectRepo) -> Shape {
        guard let column = task.column else { return .orphan }
        if repo.isIdea(task) { return .idea }
        return column.id == repo.doneColumn?.id ? .done : .pending
    }

    private static func totals(in repos: [ProjectRepo], startOfToday: Date, now: Date) -> HomeTaskTotals {
        var totals = HomeTaskTotals()
        for repo in repos {
            for task in repo.tasks ?? [] {
                switch shape(of: task, in: repo) {
                case .pending: totals.pending += 1
                case .done: totals.done += 1
                case .idea: totals.ideas += 1
                case .orphan: continue
                }
                totals.total += 1
                if task.createdAt >= startOfToday { totals.capturedToday += 1 }
                if now.timeIntervalSince(task.createdAt) <= HomeDigest.capturedWindow { totals.capturedWeek += 1 }
            }
        }
        return totals
    }

    private static func history(in repos: [ProjectRepo], startOfToday: Date, calendar: Calendar) -> [HomeDayCount] {
        let days: [Date] = (0..<historyDays).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: startOfToday)
        }
        guard let first = days.first else { return [] }
        var counts: [Date: Int] = [:]
        for task in repos.flatMap({ $0.tasks ?? [] }) where task.createdAt >= first {
            counts[calendar.startOfDay(for: task.createdAt), default: 0] += 1
        }
        return days.map { HomeDayCount(date: $0, count: counts[$0] ?? 0) }
    }

    private static func recent(in repos: [ProjectRepo]) -> [HomeRecentTask] {
        repos.flatMap { repo in
            (repo.tasks ?? []).compactMap { task -> HomeRecentTask? in
                let shape = shape(of: task, in: repo)
                guard shape != .orphan else { return nil }
                return HomeRecentTask(
                    id: task.id, title: task.content, repoName: repo.name, repoCardID: repo.homeCardID,
                    createdAt: task.createdAt, isDone: shape == .done)
            }
        }
        .sorted { $0.createdAt > $1.createdAt }
        .prefix(recentLimit)
        .map { $0 }
    }

    private static func busiest(in repos: [ProjectRepo]) -> [HomeRepoLoad] {
        repos.compactMap { repo -> HomeRepoLoad? in
            var pending = 0
            var total = 0
            for task in repo.tasks ?? [] {
                switch shape(of: task, in: repo) {
                case .pending: pending += 1; total += 1
                case .done: total += 1
                case .idea, .orphan: continue
                }
            }
            guard pending > 0 else { return nil }
            return HomeRepoLoad(id: repo.homeCardID, name: repo.name, pending: pending, total: total)
        }
        .sorted { $0.pending > $1.pending }
        .prefix(busiestLimit)
        .map { $0 }
    }

    private static func github(
        in repos: [ProjectRepo], activity: (Int) -> RepoActivity?, now: Date
    ) -> HomeGitHubSummary {
        var summary = HomeGitHubSummary()
        var pushes: [HomeRepoPush] = []
        for repo in repos where !repo.isLocal {
            guard let facts = activity(repo.repoID) else { continue }
            summary.known += 1
            summary.openPullRequests += facts.openPullRequests
            if facts.isBuildFailing { summary.failing.append(repo.name) }
            summary.securityAlerts += facts.securityAlerts ?? 0
            if facts.isPrivate { summary.privateRepos += 1 } else { summary.publicRepos += 1 }
            if let pushed = facts.pushedAt {
                pushes.append(HomeRepoPush(id: repo.homeCardID, name: repo.name, pushedAt: pushed))
                let age = now.timeIntervalSince(pushed)
                if age <= 24 * 60 * 60 { summary.pushedToday += 1 }
                if age <= HomeDigest.capturedWindow { summary.pushedWeek += 1 }
            }
            if let tag = facts.latestReleaseTag {
                summary.releases.append(HomeRepoRelease(id: repo.homeCardID, name: repo.name, tag: tag))
            }
        }
        summary.recentPushes = Array(pushes.sorted { $0.pushedAt > $1.pushedAt }.prefix(5))
        return summary
    }

    private static func languages(in repos: [ProjectRepo]) -> [HomeLanguageShare] {
        Dictionary(grouping: repos.compactMap(\.language), by: { $0 })
            .map { HomeLanguageShare(id: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
            .prefix(5)
            .map { $0 }
    }
}

extension HomeAppSummary {
    init?(repo: ProjectRepo, stats: RepoStats) {
        guard let app = HomeDigestApp(repo: repo, stats: stats) else { return nil }
        let primaryKey = stats.primaryHeadline?.key
        self.init(
            app: app,
            headlines: stats.headline
                .filter { $0.key != primaryKey }
                .compactMap { item in
                    item.value.map { HomeHeadlineValue(id: item.key, label: item.label, value: $0) }
                }
                .prefix(4)
                .map { $0 },
            sparkline: stats.series.first?.points.map(\.value) ?? [],
            periodDays: stats.periodDays)
    }
}
