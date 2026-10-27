import SwiftData
import SwiftUI

/// Where the user can go from the home screen besides a board.
enum HomeRoute: Hashable {
    case today
    case profile
    case apps
    case digest(HomeDigestKind)
    case stats(ProjectRepo)
    /// A board opened from a notification, on the task, the column or the report it was about.
    case board(ProjectRepo, BoardFocus?)
}

// MARK: - Live home

/// The redesigned home on iPhone: the tab bar, the four tabs, and everything the repos tab
/// needs from the app.
///
/// `HomeView` knows nothing about models. This is the one place that turns `ProjectRepo` plus
/// `RepoActivity` into card data, syncs with GitHub, answers every `HomeActions` closure, and
/// pushes the board when a card is tapped. Today, Profile and Settings are the existing screens
/// embedded under the home's own header, inside the same navigation stack.
struct HomeLiveView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \ProjectRepo.updatedAt, order: .reverse) private var repos: [ProjectRepo]
    @Query private var accounts: [GitHubAccount]
    @Query private var feedbackIssues: [FeedbackIssue]
    @Query private var folders: [RepoFolder]

    @AppStorage("isAuthenticated") private var isAuthenticated = false
    @AppStorage("isDemoMode") private var isDemoMode = false
    @AppStorage("lastSyncTimestamp") private var lastSyncTimestamp: Double = 0
    @AppStorage("lastTaskImportTimestamp") private var lastTaskImport: Double = 0

    @State private var subscription = SubscriptionManager.shared
    @State private var activity = RepoActivityStore.shared
    @State private var statsStore = RepoStatsStore.shared
    @State private var storeStore = StoreStatusStore.shared
    @State private var notifications = NotificationRouter.shared
    @State private var path = NavigationPath()
    @State private var tab: HomeTab = .start
    @State private var selectedAccount: String?
    @State private var isSearching = false
    @State private var searchText = ""
    /// `searchText` once typing has paused: what the lists filter by. They rebuilt on every keystroke.
    @State private var query = ""
    /// Moves when the day changes or the app comes back, so that "today" is today again: the start screen
    /// stayed on yesterday's date and counts until something unrelated redrew it.
    @State private var dayTick = Date.now
    @FocusState private var searchFocused: Bool
    @State private var isSyncing = false
    @State private var showAddLocalProject = false
    @State private var showPaywall = false
    @State private var showSignOutConfirm = false
    /// Set when a sync fails with an expired token, so the user can replace it without signing out.
    @State private var expiredTokenAccount: GitHubAccount?
    @State private var repoToFile: ProjectRepo?
    @State private var repoToConfigureIcon: ProjectRepo?

    private let syncMonitor = CloudKitSyncMonitor.shared

    private static let syncSuccessFeedback = UINotificationFeedbackGenerator()

    var body: some View {
        let _ = dayTick
        NavigationStack(path: $path) {
            ZStack {
                HomeTheme.background
                    .ignoresSafeArea()
                switch tab {
                case .start:
                    HomeDashboardView(data: dashboard, account: accountMenuData, actions: dashboardActions)
                case .repos:
                    reposTab
                case .tasks:
                    HomeTasksView(
                        rows: taskRows, attention: attentionCount, searchText: query,
                        actions: HomeTasksActions(
                            openRepo: dashboardActions.openRepo,
                            openToday: { path.append(HomeRoute.today) },
                            refresh: { await refresh() }))
                case .settings:
                    tabPage("settings_title") {
                        SettingsView(embedded: true, onOpenProfile: { path.append(HomeRoute.profile) })
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ProjectRepo.self) { repo in
                BoardView(project: repo)
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .today: onBlack { TodayView() }
                case .profile: profilePage
                case .apps:
                    HomeAppsPanelView(
                        entries: appEntries, isPro: subscription.isPro,
                        actions: HomeAppsPanelActions(
                            openStats: dashboardActions.openStats,
                            upgrade: { showPaywall = true },
                            refresh: { await refresh() }))
                case .digest(let kind): onBlack { HomeDigestView(kind: kind, scope: entitledRepos) }
                case .stats(let repo): BoardStatsView(project: repo)
                case .board(let repo, let focus): BoardView(project: repo, focus: focus)
                }
            }
            // A tap on a notification: now if the repos are here, or when they arrive from iCloud on
            // a launch that started with the tap.
            .onChange(of: notifications.pending) { _, _ in openPendingNotification() }
            .onChange(of: repos.count) { _, _ in openPendingNotification() }
            .task { openPendingNotification() }
            .sheet(isPresented: $showAddLocalProject) {
                AddLocalProjectSheet()
                    .environment(\.modelContext, context)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(item: $expiredTokenAccount) { account in
                ReauthSheet(account: account)
            }
            .sheet(item: $repoToFile) { repo in
                FolderPickerSheet(repo: repo)
            }
            .sheet(item: $repoToConfigureIcon) { repo in
                RepoIconConfigSheet(repo: repo)
            }
            .confirmationDialog(
                "home_sign_out_confirm_title", isPresented: $showSignOutConfirm, titleVisibility: .visible
            ) {
                Button("sign_out", role: .destructive) { signOut() }
                Button("cancel_button", role: .cancel) {}
            } message: {
                Text("home_sign_out_confirm_message")
            }
            // Once on appear and again whenever repos arrive, as they do from CloudKit on a fresh
            // device. A first launch with nothing local fetches the repo list; the activity
            // store's hour-long cache makes the extra runs free.
            .task(id: repos.count) {
                if repos.isEmpty {
                    await syncRepos(silent: true)
                }
                await refreshCaches()
            }
            // Coming back to the app: what the day changed, what GitHub closed while it was away (the
            // classic list does this; here it only happened on a pull), and the caches that went stale.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                dayTick = .now
                Task {
                    await importAgentCompletedTasks(force: false)
                    await refreshCaches()
                }
            }
            .task {
                // This task stops while a board or Today is pushed over the home, and restarts on the way
                // back: a midnight that passed in between is noticed here.
                if !Calendar.current.isDate(dayTick, inSameDayAs: .now) { dayTick = .now }
                for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                    dayTick = .now
                }
            }
            // Typing is not filtering: the lists wait for a pause.
            .task(id: searchText) {
                if !searchText.isEmpty {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                guard !Task.isCancelled else { return }
                query = searchText
            }
        }
    }

    /// The caches that go stale: activity, App Store status and every connected app's statistics. Each
    /// keeps its own hour, so calling this often is free.
    private func refreshCaches() async {
        statsStore.loadCached(for: repos.map(\.repoID))
        storeStore.loadCached()
        await activity.refresh(repos: repos, accounts: accounts)
        await storeStore.refresh(accounts: storeAccounts)
        for repoID in repos.map(\.repoID) where statsStore.isConfigured(repoID) {
            await statsStore.refresh(repoID: repoID)
        }
    }

    /// The logins the store status can read its file with.
    private var storeAccounts: [StoreAccount] {
        accounts.map { StoreAccount(username: $0.username, tokenKey: $0.tokenKey) }
    }

    // MARK: Notifications

    /// Takes the target the last tap left in the router and goes there, from the root, so the back
    /// button leads home and not through whatever was open. A target that no longer resolves (the
    /// report was deleted, the repo removed) is dropped rather than kept for ever.
    private func openPendingNotification() {
        guard let target = notifications.pending, !repos.isEmpty || !target.needsRepos else { return }
        notifications.clear()
        guard let destination = target.destination(repos: repos, feedback: feedbackIssues) else { return }
        switch destination {
        case .board(let repo, let focus):
            path = NavigationPath()
            path.append(HomeRoute.board(repo, focus))
        case .stats(let repo):
            path = NavigationPath()
            path.append(HomeRoute.stats(repo))
        case .web(let url):
            openURL(url)
        }
    }

    // MARK: Tabs

    private var accountMenuData: HomeAccountMenuData {
        HomeAccountMenuData(
            names: accountNames, selected: selectedAccount,
            isPro: subscription.isPro, isDemo: isDemoMode)
    }

    /// A pushed system list on the home's black, not on the system's gray.
    private func onBlack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .scrollContentBackground(.hidden)
            .background(HomeTheme.background.ignoresSafeArea())
    }

    private var reposTab: some View {
        let cards = self.cards
        return HomeView(
            account: accountMenuData,
            stats: HomeStats(cards: cards.filter { !$0.isArchived }),
            repos: cards,
            repoLimit: subscription.repoLimit,
            searchText: query,
            actions: actions
        )
    }

    // MARK: Bottom bar

    /// The tab bar with a round search button beside it, the way iOS places search now. Tapping
    /// the button swaps the row for the search field; Cancel brings the bar back.
    /// Repos and Tasks search their own lists; from the start screen the magnifier jumps to
    /// Repos, so it is always there to tap.
    private var tabSearches: Bool { tab == .repos || tab == .tasks }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if tabSearches && isSearching {
                searchField
                Button("cancel_button") { closeSearch() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeTheme.textPrimary)
            } else {
                HomeTabBar(selection: $tab)
                if tab != .settings {
                    Button {
                        if !tabSearches {
                            withAnimation(.snappy(duration: 0.25)) { tab = .repos }
                        }
                        isSearching = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(HomeTheme.textPrimary)
                            .frame(width: 52, height: 52)
                            .background(Circle().fill(HomeTheme.surface))
                            .overlay(Circle().strokeBorder(HomeTheme.hairline, lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("home_search_label")
                }
            }
        }
        .padding(.horizontal, HomeTheme.gutter)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            LinearGradient(
                colors: [HomeTheme.background.opacity(0), HomeTheme.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .animation(.snappy(duration: 0.25), value: isSearching)
        .onChange(of: isSearching) { _, searching in searchFocused = searching }
        .onChange(of: tab) { _, newTab in
            // Repos and Tasks share the search; leaving both closes it.
            if isSearching, newTab != .repos, newTab != .tasks { closeSearch() }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(HomeTheme.textSecondary)
            TextField(tab == .tasks ? "search_tasks_placeholder" : "search_placeholder", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(HomeTheme.textPrimary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(HomeTheme.textSecondary)
                        .homeHitArea(extending: 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("home_clear_search_label")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(Capsule().fill(HomeTheme.surface))
        .overlay(Capsule().strokeBorder(HomeTheme.hairline, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }

    private func closeSearch() {
        searchText = ""
        isSearching = false
    }

    private func tabPage<Content: View>(
        _ title: LocalizedStringKey, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(HomeTheme.textPrimary)
                .padding(.horizontal, HomeTheme.gutter)
                .padding(.top, 8)
                .padding(.bottom, 4)
            content()
                .scrollContentBackground(.hidden)
        }
    }

    // MARK: Actions

    private var actions: HomeActions {
        HomeActions(
            selectRepo: { card in withRepo(card) { path.append($0) } },
            toggleFavorite: { card in withRepo(card) { repo in Task { await toggleFavorite(repo) } } },
            toggleArchive: { card in withRepo(card) { repo in withAnimation { repo.isArchived.toggle() } } },
            delete: { card in withRepo(card) { repo in withAnimation { context.delete(repo) } } },
            moveToFolder: { card in withRepo(card) { repoToFile = $0 } },
            configureIcon: { card in withRepo(card) { repoToConfigureIcon = $0 } },
            openOnGitHub: { card in
                withRepo(card) { repo in
                    if let url = URL(string: repo.htmlURL) { openURL(url) }
                }
            },
            selectAccount: { selectedAccount = $0 },
            upgrade: { showPaywall = true },
            signOut: { showSignOutConfirm = true },
            add: { showAddLocalProject = true },
            notifications: { path.append(HomeRoute.today) },
            refresh: { await refresh() }
        )
    }

    // MARK: Start screen

    /// Profile, pushed from Settings: the accounts, the plan and the way out.
    private var profilePage: some View {
        ZStack {
            HomeTheme.background
                .ignoresSafeArea()
            HomeProfileView(
                onUpgrade: { showPaywall = true },
                onSignOut: { showSignOutConfirm = true }
            )
        }
        .navigationTitle("home_tab_profile")
    }

    /// The repos of the selected account that its plan shows, in the order of the Repos tab: favorites
    /// first, then the most recently updated, cut to `repoLimit` on a free account. The cap used to exist
    /// only in that list, so the start screen, the tasks, the digests and the apps panel counted, listed
    /// and opened repos the free tier hides.
    private var entitledRepos: [ProjectRepo] {
        let mine = repos.filter {
            !$0.isArchived && (selectedAccount == nil || $0.account?.username == selectedAccount)
        }
        let ordered = mine.filter(\.isFavorite) + mine.filter { !$0.isFavorite }
        return SubscriptionManager.visible(ordered, limit: subscription.repoLimit, isFavorite: \.isFavorite)
    }

    /// What the home counts: the repos the plan shows for the selected account, and its archived ones
    /// (counted apart). The start screen and the attention row must agree, so both read this.
    private var countedRepos: [ProjectRepo] {
        let archived = repos.filter {
            $0.isArchived && (selectedAccount == nil || $0.account?.username == selectedAccount)
        }
        return entitledRepos + archived
    }

    /// The same repos the list shows: the selected account, archived counted apart.
    private var dashboard: HomeDashboardData {
        let mine = countedRepos
        let names = Set(mine.map(\.fullName))
        let unread = feedbackIssues.filter {
            !$0.isRead && !$0.isSnoozed && $0.state == "open" && names.contains($0.repoFullName)
        }
        return HomeDashboardData(
            repos: mine,
            accounts: accounts,
            folders: folders.count,
            unreadFeedback: unread.count,
            activity: activity.activity(for:),
            stats: statsStore.stats(for:),
            sync: HomeSyncStatus(
                iCloudProblem: syncMonitor.hasSyncProblem
                    ? (syncMonitor.lastErrorDetail ?? syncMonitor.lastErrorMessage) : nil,
                iCloudLastSuccess: syncMonitor.lastSuccessDate,
                lastGitHubSync: lastSyncTimestamp > 0 ? Date(timeIntervalSince1970: lastSyncTimestamp) : nil,
                activityRefreshedAt: activity.lastRefresh),
            isPro: subscription.isPro,
            store: storeStore.status,
            // When the file was written, not when it was fetched: a workflow that stopped running
            // leaves a file that looks freshly downloaded every hour.
            storeUpdatedAt: storeStore.status?.generatedAt
        )
    }

    /// Every connected app of the selected account with what its backend last said.
    private var appEntries: [HomeAppPanelEntry] {
        entitledRepos
            .compactMap { repo in
                statsStore.stats(for: repo.repoID).map {
                    HomeAppPanelEntry(
                        repoID: repo.repoID, name: repo.name, stats: $0, fetchedAt: statsStore.fetchedAt[repo.repoID])
                }
            }
    }

    /// Every task of the selected account's live repos, newest first.
    private var taskRows: [HomeTaskRow] {
        HomeTaskRow.rows(in: entitledRepos)
    }

    /// What Today lists: unread reports, tasks never published, and a sync that is failing. Counted
    /// directly: this used to build the whole start screen (every task walked eight times) just to read
    /// two of its numbers, on every redraw of the Tasks tab.
    private var attentionCount: Int {
        let scope = countedRepos
        let names = Set(scope.map(\.fullName))
        let unread = feedbackIssues.filter {
            !$0.isRead && !$0.isSnoozed && $0.state == "open" && names.contains($0.repoFullName)
        }.count
        return unread + HomeDigest.unpublishedTasks(in: scope).count + (syncMonitor.hasSyncProblem ? 1 : 0)
    }

    private var dashboardActions: HomeDashboardActions {
        HomeDashboardActions(
            openRepo: { id in
                if let repo = repos.first(where: { $0.homeCardID == id }) { path.append(repo) }
            },
            selectAccount: { selectedAccount = $0 },
            upgrade: { showPaywall = true },
            signOut: { showSignOutConfirm = true },
            openDigest: { kind in
                // Today already lists these two, with the retry button; no second screen.
                switch kind {
                case .unpublished, .feedback: path.append(HomeRoute.today)
                default: path.append(HomeRoute.digest(kind))
                }
            },
            openStats: { repoID in
                if let repo = repos.first(where: { $0.repoID == repoID }) { path.append(HomeRoute.stats(repo)) }
            },
            openToday: { path.append(HomeRoute.today) },
            openApps: { path.append(HomeRoute.apps) },
            showRepos: { withAnimation(.snappy(duration: 0.25)) { tab = .repos } },
            refresh: { await refresh() }
        )
    }

    /// "31 Activas 7 días": the headline the app's stats endpoint marks as primary.
    private func highlight(for repo: ProjectRepo) -> String? {
        guard !repo.isLocal, let headline = statsStore.stats(for: repo.repoID)?.primaryHeadline,
              let value = headline.value
        else { return nil }
        return value.formatted() + " " + headline.label
    }

    private func withRepo(_ card: HomeRepoCardData, _ body: (ProjectRepo) -> Void) {
        guard let repo = repos.first(where: { $0.homeCardID == card.id }) else { return }
        body(repo)
    }

    /// Stars or unstars on GitHub as well, and rolls the local flag back if that fails.
    private func toggleFavorite(_ repo: ProjectRepo) async {
        let wasStarred = repo.isFavorite
        repo.isFavorite.toggle()
        guard let account = repo.account, !repo.isLocal else { return }
        do {
            guard let token = try await KeychainManager.shared.retrieveToken(for: account.tokenKey) else { return }
            if repo.isFavorite {
                try await GitHubService.shared.starRepo(owner: account.username, repo: repo.name, token: token)
            } else {
                try await GitHubService.shared.unstarRepo(owner: account.username, repo: repo.name, token: token)
            }
        } catch {
            repo.isFavorite = wasStarred
            ToastManager.shared.show(String(localized: "github_sync_error"), style: .error)
        }
    }

    /// The classic list's sign-out: accounts, repos and the token go, demo and mock flags reset.
    private func signOut() {
        Task {
            try? context.delete(model: GitHubAccount.self)
            try? context.delete(model: ProjectRepo.self)
            if isDemoMode {
                isDemoMode = false
                SubscriptionManager.shared.isDemoMode = false
            } else {
                await SessionReset.run(context: context)
            }
            SubscriptionManager.shared.isMockPro = false
            lastSyncTimestamp = 0
            withAnimation { isAuthenticated = false }
        }
    }

    // MARK: Sync

    /// Pull-to-refresh: the repo list from GitHub, tasks an agent closed, and the activity cache.
    private func refresh() async {
        await syncRepos(silent: false)
        await importAgentCompletedTasks(force: true)
        await activity.refresh(repos: repos, accounts: accounts, force: true)
        await storeStore.refresh(accounts: storeAccounts, force: true)
    }

    /// The same sync `RepoListView` runs, minus the weekly schedule: here it happens on
    /// pull-to-refresh and on a first launch with no repos.
    private func syncRepos(silent: Bool) async {
        guard !isDemoMode, !isSyncing, !accounts.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }

        // Two account rows sharing a username make every refresh insert duplicate repos.
        DuplicateRepair.run(context: context)

        // Account by account: a failure on the first must not skip the second, and the sheet that
        // replaces an expired token has to be for the account whose token expired.
        var expired: GitHubAccount?
        var failure: Error?
        for account in accounts {
            do {
                if let token = try await KeychainManager.shared.retrieveToken(for: account.tokenKey) {
                    try await GitHubService.shared.syncRepos(account: account, token: token, into: context)
                }
            } catch GitHubError.invalidToken {
                expired = expired ?? account
            } catch {
                failure = failure ?? error
            }
        }
        if let expired {
            // Not transient: offer to replace the token in place rather than signing out, which
            // would delete the local repos and their tasks.
            expiredTokenAccount = expired
        } else if let failure {
            if !silent {
                ToastManager.shared.show(failure.localizedDescription, style: .error)
            }
        } else {
            lastSyncTimestamp = Date().timeIntervalSince1970
            if !silent {
                ToastManager.shared.show(String(localized: "repos_synced_toast"), style: .success)
                Self.syncSuccessFeedback.notificationOccurred(.success)
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

    private var accountNames: [String] {
        accounts.map(\.username).filter { $0 != "demo-user" || isDemoMode }
    }

    private var unreadFeedbackByRepo: [String: Int] {
        feedbackIssues
            .filter { !$0.isRead && !$0.isSnoozed && $0.state == "open" }
            .reduce(into: [:]) { counts, issue in counts[issue.repoFullName, default: 0] += 1 }
    }

    /// Every repo of the selected account, favorites first, archived included — the filter
    /// chips decide what shows, and the free-tier gate is applied after them, in `HomeView`.
    private var cards: [HomeRepoCardData] {
        let unread = unreadFeedbackByRepo
        let sorted = repos
            .filter { selectedAccount == nil || $0.account?.username == selectedAccount }
            .sorted { lhs, rhs in
                if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
                return lhs.updatedAt > rhs.updatedAt
            }
        var cards = sorted.map { repo in
            var card = HomeRepoCardData(
                repo: repo,
                unreadFeedback: unread[repo.fullName] ?? 0,
                activity: activity.activity(for: repo.repoID)
            )
            card.highlight = highlight(for: repo)
            return card
        }
        if let hero = cards.firstIndex(where: { !$0.isArchived }) {
            cards[hero].isFeatured = true
        }
        return cards
    }
}
