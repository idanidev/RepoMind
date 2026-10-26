import SwiftData
import SwiftUI

/// Where the user can go from the home screen besides a board.
enum HomeRoute: Hashable {
    case today
}

// MARK: - Live home

/// The redesigned home fed from SwiftData and the activity cache.
///
/// `HomeView` knows nothing about models. This is the one place that turns `ProjectRepo` plus
/// `RepoActivity` into card data, applies the free-tier limit the same way `RepoListView` does,
/// syncs with GitHub on pull-to-refresh, and pushes the board when a card is tapped. Tasks and
/// Settings in the tab bar open the existing screens.
struct HomeLiveView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ProjectRepo.updatedAt, order: .reverse) private var repos: [ProjectRepo]
    @Query private var accounts: [GitHubAccount]
    @Query private var feedbackIssues: [FeedbackIssue]

    @AppStorage("isDemoMode") private var isDemoMode = false
    @AppStorage("lastSyncTimestamp") private var lastSyncTimestamp: Double = 0
    @AppStorage("lastTaskImportTimestamp") private var lastTaskImport: Double = 0

    @State private var subscription = SubscriptionManager.shared
    @State private var activity = RepoActivityStore.shared
    @State private var path = NavigationPath()
    @State private var showAddLocalProject = false
    @State private var showSettings = false
    @State private var isSyncing = false
    /// Set when a sync fails with an expired token, so the user can replace it without signing out.
    @State private var expiredTokenAccount: GitHubAccount?

    var body: some View {
        NavigationStack(path: $path) {
            home
        }
    }

    private var home: some View {
        let cards = self.cards
        return HomeView(
            accountName: accountName,
            stats: HomeStats(cards: cards),
            repos: cards,
            onSelectRepo: open,
            onAdd: { showAddLocalProject = true },
            onNotifications: { path.append(HomeRoute.today) },
            onRefresh: { await refresh(force: true) },
            onSelectTab: handle
        )
        .navigationDestination(for: ProjectRepo.self) { repo in
            KanbanView(project: repo)
        }
        .navigationDestination(for: HomeRoute.self) { route in
            switch route {
            case .today: TodayView()
            }
        }
        .sheet(isPresented: $showAddLocalProject) {
            AddLocalProjectSheet()
                .environment(\.modelContext, context)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $expiredTokenAccount) { account in
            ReauthSheet(account: account)
        }
        // Once on appear and again whenever repos arrive, as they do from CloudKit on a fresh
        // device. A first launch with nothing local fetches the repo list; the activity store's
        // hour-long cache makes the extra runs free.
        .task(id: repos.count) {
            if repos.isEmpty {
                await syncRepos(silent: true)
            }
            await activity.refresh(repos: repos, accounts: accounts)
        }
    }

    // MARK: Navigation

    private func open(_ card: HomeRepoCardData) {
        guard let repo = visibleRepos.first(where: { $0.homeCardID == card.id }) else { return }
        path.append(repo)
    }

    private func handle(_ tab: HomeTab) -> Bool {
        switch tab {
        case .tasks:
            path.append(HomeRoute.today)
            return true
        case .settings:
            showSettings = true
            return true
        case .repos, .profile:
            return false
        }
    }

    // MARK: Sync

    /// Pull-to-refresh: the repo list from GitHub, tasks an agent closed, and the activity cache.
    private func refresh(force: Bool) async {
        await syncRepos(silent: !force)
        await importAgentCompletedTasks(force: force)
        await activity.refresh(repos: repos, accounts: accounts, force: force)
    }

    /// The same sync `RepoListView` runs, minus the weekly schedule: here it happens on
    /// pull-to-refresh and on a first launch with no repos.
    private func syncRepos(silent: Bool) async {
        guard !isDemoMode, !isSyncing, !accounts.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }

        // Two account rows sharing a username make every refresh insert duplicate repos.
        DuplicateRepair.run(context: context)

        do {
            for account in accounts {
                if let token = try await KeychainManager.shared.retrieveToken(for: account.tokenKey) {
                    try await GitHubService.shared.syncRepos(account: account, token: token, into: context)
                }
            }
            lastSyncTimestamp = Date().timeIntervalSince1970
            if !silent {
                ToastManager.shared.show(String(localized: "repos_synced_toast"), style: .success)
            }
        } catch GitHubError.invalidToken {
            // Not transient: offer to replace the token in place rather than signing out, which
            // would delete the local repos and their tasks.
            expiredTokenAccount = accounts.first { $0.username != "demo-user" }
        } catch {
            if !silent {
                ToastManager.shared.show(error.localizedDescription, style: .error)
            }
        }
    }

    /// Pulls in tasks an agent closed on GitHub, without having to open each board. Throttled to
    /// two minutes unless forced by pull-to-refresh, which always answers with a toast.
    private func importAgentCompletedTasks(force: Bool) async {
        guard !isDemoMode else { return }
        let now = Date().timeIntervalSince1970
        guard force || now - lastTaskImport > 120 else { return }
        lastTaskImport = now

        let outcome = await TaskIssueSyncService.shared.syncIssuesEverywhere(repos: repos, context: context)
        switch outcome {
        case .changed(let result):
            ToastManager.shared.show(TaskIssueSyncService.summary(for: result), style: .success)
            for _ in 0..<result.completed { ReviewPrompter.recordCompletedTask() }
        case .syncDisabled where force:
            ToastManager.shared.show(String(localized: "task_import_sync_off"), style: .info)
        case .upToDate where force:
            ToastManager.shared.show(String(localized: "task_import_up_to_date"), style: .info)
        case .requestFailed(let reason) where force:
            ToastManager.shared.show(reason, style: .error)
        default:
            break
        }
    }

    // MARK: Data

    private var accountName: String? {
        accounts.first { $0.username != "demo-user" }?.username ?? accounts.first?.username
    }

    /// Archived repos stay out, favorites come first, and a free account sees at most
    /// `maxFreeRepos` — the same gate as the list it replaces, so switching screens never
    /// shows a free user more than the tier allows.
    private var visibleRepos: [ProjectRepo] {
        var sorted = repos
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
                return lhs.updatedAt > rhs.updatedAt
            }
        if !subscription.isPro, sorted.count > subscription.maxFreeRepos {
            let limit = subscription.maxFreeRepos
            let favorites = Array(sorted.filter(\.isFavorite).prefix(limit))
            let nonFavorites = sorted.filter { !$0.isFavorite }
            sorted = favorites + Array(nonFavorites.prefix(max(0, limit - favorites.count)))
        }
        return sorted
    }

    private var unreadFeedbackByRepo: [String: Int] {
        feedbackIssues
            .filter { !$0.isRead && !$0.isSnoozed && $0.state == "open" }
            .reduce(into: [:]) { counts, issue in counts[issue.repoFullName, default: 0] += 1 }
    }

    private var cards: [HomeRepoCardData] {
        let unread = unreadFeedbackByRepo
        return visibleRepos.enumerated().map { index, repo in
            var card = HomeRepoCardData(
                repo: repo,
                unreadFeedback: unread[repo.fullName] ?? 0,
                activity: activity.activity(for: repo.repoID)
            )
            card.isFeatured = index == 0
            return card
        }
    }
}
