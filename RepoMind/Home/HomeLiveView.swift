import SwiftData
import SwiftUI

/// Where the user can go from the home screen besides a board.
enum HomeRoute: Hashable {
    case today
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
    @Query(sort: \ProjectRepo.updatedAt, order: .reverse) private var repos: [ProjectRepo]
    @Query private var accounts: [GitHubAccount]
    @Query private var feedbackIssues: [FeedbackIssue]

    @AppStorage("isAuthenticated") private var isAuthenticated = false
    @AppStorage("isDemoMode") private var isDemoMode = false
    @AppStorage("lastSyncTimestamp") private var lastSyncTimestamp: Double = 0
    @AppStorage("lastTaskImportTimestamp") private var lastTaskImport: Double = 0

    @State private var subscription = SubscriptionManager.shared
    @State private var activity = RepoActivityStore.shared
    @State private var statsStore = RepoStatsStore.shared
    @State private var path = NavigationPath()
    @State private var tab: HomeTab = .repos
    @State private var selectedAccount: String?
    @State private var isSearching = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var isSyncing = false
    @State private var showAddLocalProject = false
    @State private var showPaywall = false
    @State private var showSignOutConfirm = false
    /// Set when a sync fails with an expired token, so the user can replace it without signing out.
    @State private var expiredTokenAccount: GitHubAccount?
    @State private var repoToFile: ProjectRepo?
    @State private var repoToConfigureIcon: ProjectRepo?

    private static let syncSuccessFeedback = UINotificationFeedbackGenerator()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                HomeTheme.background
                    .ignoresSafeArea()
                switch tab {
                case .repos:
                    reposTab
                case .tasks:
                    tabPage("today_title") { TodayView() }
                case .profile:
                    tabPage("home_tab_profile") {
                        HomeProfileView(
                            onUpgrade: { showPaywall = true },
                            onSignOut: { showSignOutConfirm = true }
                        )
                    }
                case .settings:
                    tabPage("settings_title") { SettingsView(embedded: true) }
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
                case .today: TodayView()
                }
            }
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
                statsStore.loadCached(for: repos.map(\.repoID))
                await activity.refresh(repos: repos, accounts: accounts)
                for repoID in repos.map(\.repoID) where statsStore.isConfigured(repoID) {
                    await statsStore.refresh(repoID: repoID)
                }
            }
        }
    }

    // MARK: Tabs

    private var reposTab: some View {
        let cards = self.cards
        return HomeView(
            account: HomeAccountMenuData(
                names: accountNames, selected: selectedAccount,
                isPro: subscription.isPro, isDemo: isDemoMode),
            stats: HomeStats(cards: cards.filter { !$0.isArchived }),
            repos: cards,
            repoLimit: subscription.isPro ? nil : subscription.maxFreeRepos,
            searchText: searchText,
            actions: actions
        )
    }

    // MARK: Bottom bar

    /// The tab bar with a round search button beside it, the way iOS places search now. Tapping
    /// the button swaps the row for the search field; Cancel brings the bar back.
    private var bottomBar: some View {
        HStack(spacing: 10) {
            if tab == .repos && isSearching {
                searchField
                Button("cancel_button") { closeSearch() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeTheme.textPrimary)
            } else {
                HomeTabBar(selection: $tab)
                if tab == .repos {
                    Button {
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
        .onChange(of: tab) { _, _ in
            if isSearching { closeSearch() }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(HomeTheme.textSecondary)
            TextField("search_placeholder", text: $searchText)
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
                try? await KeychainManager.shared.deleteToken()
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
                Self.syncSuccessFeedback.notificationOccurred(.success)
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
