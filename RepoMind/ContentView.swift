import Combine
import CloudKit
import PhotosUI
import SwiftData
import SwiftUI

// MARK: - Content View (Root Navigation)

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("isAuthenticated") private var isAuthenticated = false
    @AppStorage("isDemoMode") private var isDemoMode = false
    @Query private var accounts: [GitHubAccount]

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    /// Waiting for CloudKit to deliver accounts on first launch of a new device
    @State private var isAwaitingCloudKit = true

    /// Only on a genuinely new install. A device that already has an account signed in — or one
    /// whose data is still arriving from CloudKit — has clearly been through this before.
    private var showOnboarding: Binding<Bool> {
        Binding(
            get: { !hasSeenOnboarding && !shouldShowMain && !isAwaitingCloudKit },
            set: { if !$0 { hasSeenOnboarding = true } }
        )
    }

    private var shouldShowMain: Bool {
        // Demo mode: show main only while demo is active
        if isDemoMode { return !accounts.isEmpty }
        // Real mode: ignore demo accounts (they may linger from a previous session or CloudKit sync)
        return isAuthenticated || accounts.contains { $0.username != "demo-user" }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if isAwaitingCloudKit && !shouldShowMain {
                    iCloudSyncingView
                } else if shouldShowMain {
                    if horizontalSizeClass == .regular {
                        AdaptiveRepoListView()
                    } else {
                        RepoListView()
                    }
                } else {
                    LoginView(isAuthenticated: $isAuthenticated)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: shouldShowMain)
            .animation(.easeInOut(duration: 0.3), value: isAwaitingCloudKit)

            ToastOverlay()
        }
        // Covers the token screen on a first run: asking for a personal access token makes very
        // little sense before the app has said what it does with it.
        .fullScreenCover(isPresented: showOnboarding) {
            OnboardingView()
        }
        .task {
            #if DEBUG
            if isDemoMode {
                isAwaitingCloudKit = false
                SubscriptionManager.shared.isDemoMode = true
            } else {
                purgeStaleDemo()
                await waitForCloudKitAccounts()
            }
            #else
            // In production, demo mode is not supported — always clean up
            if isDemoMode {
                isDemoMode = false
                purgeStaleDemo()
            }
            await waitForCloudKitAccounts()
            #endif
            // Again after the CloudKit wait: a repo whose columns had not arrived yet was skipped
            // the first time. Repairing an already-repaired task is a no-op.
            repairOrphanTasks()
        }
        // `initial: true` matters: on a device that is already signed in, `shouldShowMain` is
        // true from the very first evaluation, so a plain onChange would never fire at all.
        .onChange(of: shouldShowMain, initial: true) { _, showing in
            guard showing else { return }
            repairOrphanTasks()
        }
        .onChange(of: accounts.isEmpty) { _, isEmpty in
            // Accounts arrived via CloudKit — auto-login (ignore stale demo accounts)
            let hasRealAccounts = accounts.contains { $0.username != "demo-user" }
            if hasRealAccounts && !isDemoMode {
                isAuthenticated = true
                isAwaitingCloudKit = false
            }
        }
    }

    /// Reattaches tasks that lost their column, and says so — silently fixing eight missing tasks
    /// would leave the same "where did my task go?" question, just with a different answer.
    private func repairOrphanTasks() {
        // Duplicates first: merging two copies of a repo moves tasks between them, and reattaching
        // orphans afterwards means they land on the surviving board rather than one about to go.
        let dupes = DuplicateRepair.run(context: context)
        if dupes.changed {
            ToastManager.shared.show(
                String(
                    format: String(localized: "duplicates_merged %lld %lld"),
                    dupes.reposMerged, dupes.accountsMerged),
                style: .info
            )
        }

        let repaired = OrphanTaskRepair.run(context: context)
        guard repaired > 0 else { return }
        ToastManager.shared.show(
            String(format: String(localized: "orphan_tasks_restored %lld"), repaired),
            style: .info
        )
    }

    // MARK: - CloudKit startup sync

    private var iCloudSyncingView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            ProgressView()
                .scaleEffect(1.2)
            Text("icloud_syncing_message")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                isAwaitingCloudKit = false
            } label: {
                Text("icloud_sign_in_manually")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Deletes any persisted demo accounts / negative-ID repos so they don't
    /// interfere with real account detection or subscription counts.
    private func purgeStaleDemo() {
        let accountDesc = FetchDescriptor<GitHubAccount>(
            predicate: #Predicate { $0.username == "demo-user" }
        )
        if let existing = try? context.fetch(accountDesc) {
            existing.forEach { context.delete($0) }
        }
        let repoDesc = FetchDescriptor<ProjectRepo>(
            predicate: #Predicate { $0.repoID < 0 }
        )
        if let existing = try? context.fetch(repoDesc) {
            existing.forEach { context.delete($0) }
        }
    }

    /// On a fresh device, give CloudKit up to 30 s to deliver accounts before showing LoginView.
    /// First does a quick CKQuery — if no records exist in iCloud, goes straight to LoginView.
    private func waitForCloudKitAccounts() async {
        guard !shouldShowMain else {
            isAwaitingCloudKit = false
            return
        }

        let status = try? await CKContainer.default().accountStatus()
        guard status == .available else {
            isAwaitingCloudKit = false
            return
        }

        let hasData = await cloudKitHasAccounts()
        guard hasData else {
            isAwaitingCloudKit = false
            return
        }

        let deadline = Date().addingTimeInterval(30)
        while accounts.isEmpty && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(500))
        }

        isAwaitingCloudKit = false
    }

    private func cloudKitHasAccounts() async -> Bool {
        let db = CKContainer(identifier: "iCloud.idanidev.RepoMind").privateCloudDatabase
        do {
            let zones = try await db.allRecordZones()
            return zones.contains { $0.zoneID.zoneName == "com.apple.coredata.cloudkit.zone" }
        } catch {
            return false
        }
    }
}

// MARK: - Repo Filter

enum RepoFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case archived

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .all: "filter_all"
        case .favorites: "filter_favorites"
        case .archived: "filter_archived"
        }
    }

    var iconName: String {
        switch self {
        case .all: "folder"
        case .favorites: "star.fill"
        case .archived: "archivebox"
        }
    }
}

// MARK: - Repo List View

struct RepoListView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("isAuthenticated") private var isAuthenticated = false
    @AppStorage("isDemoMode") private var isDemoMode = false
    @Query(sort: \ProjectRepo.updatedAt, order: .reverse) private var repos: [ProjectRepo]
    @Query private var accounts: [GitHubAccount]

    @State private var isLoading = false
    @State private var searchText = ""
    @State private var activeFilter: RepoFilter = .all
    @State private var selectedAccount: GitHubAccount?

    // ✅ FIX: Cached filtered repos (Performance)
    @State private var filteredRepos: [ProjectRepo] = []

    @AppStorage("lastSyncTimestamp") private var lastSyncTimestamp: Double = 0
    private let autoSyncInterval: TimeInterval = 7 * 24 * 60 * 60 // 1 week

    @State private var isWaitingForCloudKit = false

    private var shouldAutoSync: Bool {
        repos.isEmpty || Date().timeIntervalSince1970 - lastSyncTimestamp > autoSyncInterval
    }

    var body: some View {
        NavigationStack {
            Group {
                if (repos.isEmpty && isLoading) || isWaitingForCloudKit {
                    cloudKitWaitingView
                } else if repos.isEmpty {
                    emptyState
                } else {
                    repoList
                }
            }
            .navigationTitle("repositories_title")
            .searchable(text: $searchText, prompt: "search_placeholder")
            .toolbar { toolbarContent }
            .refreshable {
                await syncRepos()
                await importAgentCompletedTasks(force: true)
            }
            .task {
                updateFilteredRepos()
                if repos.isEmpty {
                    await waitForCloudKitThenSync()
                } else if shouldAutoSync {
                    await syncRepos(silent: true)
                }
                await importAgentCompletedTasks()
            }
            // `.task` fires when the view is created, and coming back from the background does
            // not create it again — the view was alive the whole time. So the only thing that
            // refreshed anything was opening a project, which builds a board view and runs its own
            // .task. That is exactly what "issues only update if you go into the project" was.
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await importAgentCompletedTasks() }
            }
            // Refresh when CloudKit delivers remote data
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSNotification.Name("NSPersistentStoreRemoteChangeNotification"))
                    .receive(on: RunLoop.main)
            ) { _ in
                isWaitingForCloudKit = false
                updateFilteredRepos()
            }
            // ✅ FIX: Update cache when dependencies change
            .onChange(of: repos) { _, _ in
                updateFilteredRepos()
            }
            .onChange(of: activeFilter) { _, _ in
                updateFilteredRepos()
            }
            .onChange(of: selectedAccount) { _, _ in
                updateFilteredRepos()
            }
            .onChange(of: subscription.isPro) { _, _ in
                updateFilteredRepos()
            }
            // Debounce search so filtering doesn't fire on every keystroke
            .task(id: searchText) {
                if !searchText.isEmpty {
                    try? await Task.sleep(for: .milliseconds(300))
                }
                guard !Task.isCancelled else { return }
                updateFilteredRepos()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(item: $repoToConfigureIcon) { repo in
                RepoIconConfigSheet(repo: repo)
            }
            .sheet(item: $expiredTokenAccount) { account in
                ReauthSheet(account: account)
            }
            .sheet(item: $repoToFile) { repo in
                FolderPickerSheet(repo: repo)
            }
            .sheet(isPresented: $showAddLocalProject) {
                AddLocalProjectSheet()
                    .environment(\.modelContext, context)
            }
        }
    }

    // MARK: - Cached Filtering (Performance Fix)

    private func updateFilteredRepos() {
        var result = repos

        switch activeFilter {
        case .all:
            result = result.filter { !$0.isArchived }
        case .favorites:
            result = result.filter { $0.isFavorite && !$0.isArchived }
        case .archived:
            result = result.filter { $0.isArchived }
        }

        if let account = selectedAccount {
            result = result.filter { $0.account?.id == account.id }
        }

        // ✅ FIX: Use localizedStandardContains for better search
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedStandardContains(searchText)
                    || $0.repoDescription.localizedStandardContains(searchText)
            }
        }

        var sorted = result.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.updatedAt > rhs.updatedAt
        }

        // Free-tier: show only up to the limit, prioritising favourites.
        // Applies to every filter — gating only the "all" list let a free user see an unlimited
        // number of repos just by switching to Favourites or Archived.
        if !subscription.isPro {
            let limit = subscription.maxFreeRepos
            if sorted.count > limit {
                let favorites = Array(sorted.filter { $0.isFavorite }.prefix(limit))
                let slotsForNonFav = max(0, limit - favorites.count)
                let nonFavorites = sorted.filter { !$0.isFavorite }
                sorted = favorites + Array(nonFavorites.prefix(slotsForNonFav))
            }
        }

        withAnimation(.smooth(duration: 0.35)) {
            filteredRepos = sorted
        }
    }

    // MARK: - Toolbar

    @State private var showSettings = false
    @State private var showPaywall = false
    @State private var showAddLocalProject = false
    @State private var subscription = SubscriptionManager.shared
    private static let syncSuccessFeedback = UINotificationFeedbackGenerator()
    private static let deleteImpactFeedback = UIImpactFeedbackGenerator(style: .medium)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 6) {
                accountMenu
                if isDemoMode {
                    Text("demo_mode_badge")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange, in: Capsule())
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                Button {
                    showSettings = true
                } label: {
                    Label("settings_label", systemImage: "gearshape")
                }
                .accessibilityLabel("settings_label")

                Button {
                    showAddLocalProject = true
                } label: {
                    Label("add_local_project_label", systemImage: "folder.badge.plus")
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("add_local_project_label")

                filterMenu
                if !isDemoMode { syncButton }
            }
        }
    }

    private var accountMenu: some View {
        Menu {
            Picker("accounts_filter", selection: $selectedAccount) {
                Text("all_accounts").tag(nil as GitHubAccount?)
                ForEach(accounts) { account in
                    Text(account.username).tag(account as GitHubAccount?)
                }
            }

            Divider()

            if !subscription.isPro {
                Button {
                    showPaywall = true
                } label: {
                    Label("upgrade_to_pro_button", systemImage: "crown")
                }
            }

            Button(role: .destructive, action: logout) {
                Label("sign_out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Group {
                if subscription.isPro {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.purple)
                } else if selectedAccount != nil {
                    Image(systemName: "person.crop.circle")
                } else {
                    Image(systemName: "person.2.circle")
                }
            }
            .font(.title3)
        }
        .accessibilityLabel("account_menu_label")
        .accessibilityHint(selectedAccount?.username ?? String(localized: "all_accounts"))
    }

    // ✅ FIX: Use Label instead of just Image for accessibility
    private var filterMenu: some View {
        Menu {
            ForEach(RepoFilter.allCases) { filter in
                Button {
                    withAnimation { activeFilter = filter }
                } label: {
                    Label(filter.displayName, systemImage: filter.iconName)
                }
            }
        } label: {
            Label(
                "filter_repos_label",
                systemImage: activeFilter == .all
                    ? "line.3.horizontal.decrease.circle"
                    : "line.3.horizontal.decrease.circle.fill"
            )
            .labelStyle(.iconOnly)
        }
        .accessibilityLabel("filter_repos_label")
        .accessibilityValue(Text(activeFilter.displayName))
    }

    // ✅ FIX: Use Label instead of just Image for accessibility
    private var syncButton: some View {
        Button {
            Task { await syncRepos() }
        } label: {
            if isLoading {
                ProgressView()
            } else {
                Label("sync_repos_label", systemImage: "arrow.trianglehead.2.clockwise")
                    .labelStyle(.iconOnly)
            }
        }
        .disabled(isLoading)
        .accessibilityLabel("sync_repos_label")
        .accessibilityHint(isLoading ? "syncing" : "sync_hint")
    }

    // MARK: - CloudKit Wait

    private var cloudKitWaitingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("icloud_syncing_message")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func waitForCloudKitThenSync() async {
        let status = try? await CKContainer.default().accountStatus()
        guard status == .available else {
            // iCloud not available — go straight to GitHub sync
            await syncRepos()
            return
        }

        // iCloud available: give CloudKit up to 8s to deliver remote data
        isWaitingForCloudKit = true
        let deadline = Date().addingTimeInterval(8)
        while repos.isEmpty && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(400))
        }
        isWaitingForCloudKit = false

        // Then sync with GitHub regardless
        await syncRepos()
    }

    // MARK: - Skeleton Loading

    private var skeletonList: some View {
        List {
            ForEach(0..<6, id: \.self) { _ in
                SkeletonRepoRow()
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Repo List

    private var repoList: some View {
        List {
            // Renders nothing when there is nothing waiting.
            TodayEntryRow()

            ForEach(repoSections) { section in
                Section {
                    ForEach(section.repos) { repo in
                        NavigationLink(value: repo) {
                            RepoRow(repo: repo)
                        }
                        .swipeActions(edge: .leading) {
                            favoriteButton(for: repo)
                            iconButton(for: repo)
                            folderButton(for: repo)
                        }
                        .swipeActions(edge: .trailing) {
                            deleteButton(for: repo)
                            archiveButton(for: repo)
                        }
                    }
                } header: {
                    if let folder = section.folder {
                        Label {
                            Text(folder.name)
                        } icon: {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color(hex: folder.colorHex))
                        }
                    }
                }
            }

            // Limit banner for free users — show when there are hidden repos
            if !subscription.isPro && repos.count > subscription.maxFreeRepos {
                Section {
                    Button {
                        showPaywall = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(.purple)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("repo_limit_banner_title")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(
                                    String(
                                        format: String(localized: "repo_limit_banner_subtitle"),
                                        repos.count - subscription.maxFreeRepos
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.purple.opacity(0.08))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: ProjectRepo.self) { repo in
            KanbanView(project: repo)
        }
        .overlay {
            if filteredRepos.isEmpty && !repos.isEmpty {
                emptyFilterState
            }
        }
    }

    // MARK: - Folder grouping

    private struct RepoSection: Identifiable {
        let id: String
        let folder: RepoFolder?
        let repos: [ProjectRepo]
    }

    /// The repo list split into folders, folders first and loose repos last.
    ///
    /// Empty folders are left out on purpose: a folder can only be created while filing a repo into
    /// it, so an empty one means every repo it held was deleted or moved away, and an empty header
    /// is then just noise.
    private var repoSections: [RepoSection] {
        var sections = folders.compactMap { folder -> RepoSection? in
            let inFolder = filteredRepos.filter { $0.folder?.id == folder.id }
            guard !inFolder.isEmpty else { return nil }
            return RepoSection(id: folder.id.uuidString, folder: folder, repos: inFolder)
        }
        let unfiled = filteredRepos.filter { $0.folder == nil }
        if !unfiled.isEmpty {
            sections.append(RepoSection(id: "unfiled", folder: nil, repos: unfiled))
        }
        return sections
    }

    // MARK: - Swipe Action Buttons (Extracted for clarity)

    private func folderButton(for repo: ProjectRepo) -> some View {
        Button {
            repoToFile = repo
        } label: {
            Label("move_to_folder", systemImage: "folder")
        }
        .tint(.indigo)
    }

    private func favoriteButton(for repo: ProjectRepo) -> some View {
        Button {
            Task {
                await toggleFavorite(for: repo)
            }
        } label: {
            Label(
                repo.isFavorite ? "unfavorite" : "favorite",
                systemImage: repo.isFavorite ? "star.slash" : "star.fill"
            )
        }
        .tint(.yellow)
    }

    private func toggleFavorite(for repo: ProjectRepo) async {
        let wasStarred = repo.isFavorite
        repo.isFavorite.toggle()
        updateFilteredRepos()

        guard let account = repo.account else { return }

        do {
            if let token = try await KeychainManager.shared.retrieveToken(for: account.tokenKey) {
                if repo.isFavorite {
                    try await GitHubService.shared.starRepo(
                        owner: account.username, repo: repo.name, token: token)
                } else {
                    try await GitHubService.shared.unstarRepo(
                        owner: account.username, repo: repo.name, token: token)
                }
            }
        } catch {
            repo.isFavorite = wasStarred
            updateFilteredRepos()
            ToastManager.shared.show(
                String(localized: "github_sync_error"), style: .error)
        }
    }

    private func deleteButton(for repo: ProjectRepo) -> some View {
        Button(role: .destructive) {
            Self.deleteImpactFeedback.impactOccurred()
            withAnimation { context.delete(repo) }
        } label: {
            Label("delete_task", systemImage: "trash")
        }
    }

    private func archiveButton(for repo: ProjectRepo) -> some View {
        Button {
            withAnimation {
                repo.isArchived.toggle()
                updateFilteredRepos()
            }
        } label: {
            Label(
                repo.isArchived ? "unarchive" : "archive",
                systemImage: repo.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }
        .tint(.indigo)
    }

    @State private var repoToConfigureIcon: ProjectRepo?
    /// Set when a sync fails with an expired token, so the user can replace it without signing out.
    @State private var expiredTokenAccount: GitHubAccount?
    /// The repo whose folder the user is choosing.
    @State private var repoToFile: ProjectRepo?
    @AppStorage("lastTaskImportTimestamp") private var lastTaskImport: Double = 0
    @Environment(\.scenePhase) private var scenePhase

    /// Pulls in tasks an agent closed on GitHub, without having to open each board.
    ///
    /// Kept separate from `syncRepos`, which fetches the repo list and is rate-limited enough that
    /// it deliberately runs about once a week on iPhone — hanging this off it would leave the board
    /// just as stale. Throttled to two minutes so moving in and out of the list does not fire a
    /// request per repo every time; pull-to-refresh passes `force`.
    private func importAgentCompletedTasks(force: Bool = false) async {
        guard !isDemoMode else { return }
        let now = Date().timeIntervalSince1970
        guard force || now - lastTaskImport > 120 else { return }
        lastTaskImport = now

        let outcome = await TaskIssueSyncService.shared.syncIssuesEverywhere(
            repos: repos, context: context)

        // A pull-to-refresh always answers. Saying nothing when nothing moved is exactly what made
        // this impossible to tell apart from the feature not working at all.
        switch outcome {
        case .changed(let result):
            ToastManager.shared.show(
                TaskIssueSyncService.summary(for: result), style: .success)
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
    @Query(sort: \RepoFolder.orderIndex) private var folders: [RepoFolder]

    private func iconButton(for repo: ProjectRepo) -> some View {
        Button {
            repoToConfigureIcon = repo
        } label: {
            Label("icon_configure_button", systemImage: "photo.badge.plus")
        }
        .tint(.blue)
    }

    // MARK: - Empty States

    private var emptyFilterState: some View {
        ContentUnavailableView {
            Label(
                activeFilter == .archived ? "no_archived_title" : "no_results_title",
                systemImage: activeFilter == .archived ? "archivebox" : "magnifyingglass"
            )
        } description: {
            switch activeFilter {
            case .archived:
                Text("no_archived_message")
            case .favorites:
                Text("no_favorites_message")
            case .all:
                Text("no_results_message")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("no_repos_title", systemImage: "tray")
        } description: {
            Text("connect_account_prompt")
        } actions: {
            Button("sync_button") {
                Task { await syncRepos() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func syncRepos(silent: Bool = false) async {
        guard !isDemoMode else { return }
        // Reentrancy guard: pull-to-refresh, the Cmd+R shortcut and .onAppear can all fire this
        // independently. Two overlapping runs each fetch the repo list before either has saved,
        // both see the same remote repo as new, and each inserts its own duplicate.
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        guard !accounts.isEmpty else { return }

        // Before syncing, not only at launch. Dedup inside GitHubService is scoped to one account,
        // so while two account rows share a username every refresh inserts a fresh copy of every
        // repo — and a fresh copy has `logoURL: nil`, which is why refreshing looked like it was
        // wiping the icons.
        DuplicateRepair.run(context: context)

        do {
            for account in accounts {
                if let token = try await KeychainManager.shared.retrieveToken(for: account.tokenKey)
                {
                    try await GitHubService.shared.syncRepos(
                        account: account,
                        token: token,
                        into: context
                    )
                }
            }

            lastSyncTimestamp = Date().timeIntervalSince1970

            if !silent && !repos.isEmpty {
                ToastManager.shared.show(String(localized: "repos_synced_toast"), style: .success)
                Self.syncSuccessFeedback.notificationOccurred(.success)
            }
        } catch GitHubError.invalidToken {
            // An expired token is not a transient failure: every later sync fails identically, and
            // the only way to enter a new one was signing out — which deletes the local repos and
            // their tasks. Offer to replace it in place instead. Shown even on a silent refresh,
            // because otherwise a background sync would keep failing with nothing to see.
            expiredTokenAccount = selectedAccount ?? accounts.first { $0.username != "demo-user" }
        } catch {
            if !silent {
                ToastManager.shared.show(error.localizedDescription, style: .error)
            }
        }
    }

    private func logout() {
        Task {
            if isDemoMode {
                try? context.delete(model: GitHubAccount.self)
                try? context.delete(model: ProjectRepo.self)
                isDemoMode = false
                SubscriptionManager.shared.isDemoMode = false
            } else {
                try? context.delete(model: GitHubAccount.self)
                // Repos must go with the account. `GitHubAccount.repos` is `.nullify`, so deleting
                // only the account left repos behind with `account == nil`; the per-account filter
                // never matches those, so they stayed visible under "All accounts" to whoever
                // signed in next.
                try? context.delete(model: ProjectRepo.self)
                try? await KeychainManager.shared.deleteToken()
            }
            SubscriptionManager.shared.isMockPro = false
            lastSyncTimestamp = 0
            withAnimation { isAuthenticated = false }
        }
    }
}

// MARK: - Skeleton Repo Row

struct SkeletonRepoRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("nombre-repositorio")
                    .font(.headline)
                Spacer()
                Text("Swift")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

            Text("Descripcion del repositorio placeholder que ocupa dos lineas como minimo")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack {
                Text("Hace 2 horas")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "star")
                        .font(.caption2)
                    Text("42")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

// MARK: - Repo Row

struct RepoRow: View {
    let repo: ProjectRepo
    var isSelected: Bool = false
    var unreadFeedback: Int = 0

    private var secondaryStyle: HierarchicalShapeStyle { isSelected ? .primary : .secondary }

    private var taskCount: Int {
        guard let tasks = repo.tasks, !tasks.isEmpty else { return 0 }
        let columns = repo.columns ?? []
        guard let lastColumnId = columns.max(by: { $0.orderIndex < $1.orderIndex })?.id else { return 0 }
        let validColumnIds = Set(columns.map(\.id))
        return tasks.filter { task in
            guard let columnId = task.column?.id, validColumnIds.contains(columnId) else { return false }
            return columnId != lastColumnId
        }.count
    }

    var body: some View {
        HStack(spacing: 14) {
            // Avatar del owner (de GitHub)
            avatarView

            VStack(alignment: .leading, spacing: 4) {
                // Nombre + favorito
                HStack(spacing: 6) {
                    if repo.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityHidden(true)
                    }

                    Text(repo.name)
                        .font(.headline)
                        .lineLimit(1)
                }

                // Descripción
                if !repo.repoDescription.isEmpty {
                    Text(repo.repoDescription)
                        .font(.subheadline)
                        .foregroundStyle(secondaryStyle)
                        .lineLimit(2)
                }

                // Badges: lenguaje + tareas
                HStack(spacing: 8) {
                    if let language = repo.language {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(languageColor(for: language))
                                .frame(width: 8, height: 8)
                            Text(language)
                                .font(.caption)
                        }
                        .foregroundStyle(secondaryStyle)
                    }

                    Spacer()

                    // Badge de feedback sin leer
                    if unreadFeedback > 0 {
                        ZStack {
                            Capsule().fill(Color.red)
                            HStack(spacing: 4) {
                                Image(systemName: "bell.badge.fill")
                                    .font(.caption2)
                                Text("\(unreadFeedback)")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }
                        .fixedSize()
                        .drawingGroup()
                        .accessibilityLabel(Text("feedback_unread_badge \(unreadFeedback)"))
                    }

                    // Badge de tareas destacado
                    if taskCount > 0 {
                        ZStack {
                            Capsule().fill(Color.purple)
                            HStack(spacing: 4) {
                                Image(systemName: "checklist")
                                    .font(.caption2)
                                Text("\(taskCount)")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }
                        .fixedSize()
                        .drawingGroup()
                    }

                    if repo.stargazersCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                            Text("\(repo.stargazersCount)")
                                .font(.caption)
                        }
                        .foregroundStyle(secondaryStyle)
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, isMacIdiom ? 4 : 0)
        .hoverable(cornerRadius: 8, intensity: isSelected ? 0 : 0.05)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("view_details_hint")
    }

    // Logo del repo o avatar del owner como fallback
    @ViewBuilder
    private var avatarView: some View {
        // Prioridad: 1. Logo del repo, 2. Avatar del owner, 3. Placeholder
        if let logoURL = repo.logoURL, let url = URL(string: logoURL) {
            // Logo del repositorio
            CachedAsyncImage(url: url) { ownerAvatarOrPlaceholder }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            ownerAvatarOrPlaceholder
        }
    }

    @ViewBuilder
    private var ownerAvatarOrPlaceholder: some View {
        if let avatarURL = repo.account?.avatarURL, let url = URL(string: avatarURL) {
            CachedAsyncImage(url: url) { avatarPlaceholder }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.tertiarySystemFill))
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }

    // Colores de lenguaje estilo GitHub
    private func languageColor(for language: String) -> Color {
        switch language.lowercased() {
        case "swift": return Color(hex: "#F05138")
        case "javascript", "js": return Color(hex: "#F7DF1E")
        case "typescript", "ts": return Color(hex: "#3178C6")
        case "python": return Color(hex: "#3776AB")
        case "java": return Color(hex: "#B07219")
        case "kotlin": return Color(hex: "#A97BFF")
        case "go": return Color(hex: "#00ADD8")
        case "rust": return Color(hex: "#DEA584")
        case "ruby": return Color(hex: "#CC342D")
        case "c++", "cpp": return Color(hex: "#F34B7D")
        case "c#", "csharp": return Color(hex: "#239120")
        case "php": return Color(hex: "#777BB4")
        case "html": return Color(hex: "#E34C26")
        case "css": return Color(hex: "#1572B6")
        case "shell", "bash": return Color(hex: "#89E051")
        default: return .gray
        }
    }

    private var accessibilityDescription: String {
        var parts = [repo.name]
        if repo.isFavorite {
            parts.append(String(localized: "favorite"))
        }
        parts.append(String(format: String(localized: "tasks_count"), taskCount))
        if repo.stargazersCount > 0 {
            parts.append(String(format: String(localized: "stars_count"), repo.stargazersCount))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Add Local Project Sheet

struct AddLocalProjectSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query private var allRepos: [ProjectRepo]

    @State private var name = ""
    @State private var description = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var selectedIconURL: String?

    var body: some View {
        NavigationStack {
            Form {
                // Icon picker
                Section("local_project_icon_header") {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                            Group {
                                if let urlStr = selectedIconURL, let url = URL(string: urlStr) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        default:
                                            iconPlaceholder
                                        }
                                    }
                                } else {
                                    iconPlaceholder
                                }
                            }
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white, .purple)
                                    .offset(x: 4, y: 4)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    TextField("local_project_name_placeholder", text: $name)
                        .autocorrectionDisabled()
                } header: {
                    Text("local_project_name_header")
                }

                Section {
                    TextField("local_project_description_placeholder", text: $description, axis: .vertical)
                        .lineLimit(3...5)
                } header: {
                    Text("local_project_description_header")
                } footer: {
                    Text("local_project_footer")
                }
            }
            .navigationTitle("add_local_project_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel_button") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save_button") {
                        createLocalProject()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .frame(idealWidth: 480)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await savePhoto(newItem) }
        }
    }

    private var iconPlaceholder: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color(.tertiarySystemFill))
            .overlay {
                Image(systemName: "photo.badge.plus")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
    }

    private func savePhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data),
              let jpegData = uiImage.jpegData(compressionQuality: 0.8),
              let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(UUID().uuidString + ".jpg")
        try? jpegData.write(to: fileURL)
        selectedIconURL = fileURL.absoluteString
    }

    private func createLocalProject() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        guard SubscriptionManager.shared.canAddRepo(currentCount: allRepos.count) else {
            ToastManager.shared.show(String(localized: "repo_limit_upgrade"), style: .info)
            return
        }

        let repo = ProjectRepo(
            repoID: 0,
            name: trimmedName,
            repoDescription: description.trimmingCharacters(in: .whitespacesAndNewlines),
            isLocal: true,
            logoURL: selectedIconURL
        )
        context.insert(repo)
        try? context.save()

        ToastManager.shared.show(String(localized: "local_project_created_toast"), style: .success)
        dismiss()
    }
}

// MARK: - Repo Icon Config Sheet (File Browser)

struct RepoIconConfigSheet: View {
    @Bindable var repo: ProjectRepo
    @Environment(\.dismiss) private var dismiss

    @State private var token: String?
    @State private var pathStack: [RepoContentItem] = []
    @State private var items: [RepoContentItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var isSavingPhoto = false

    private var owner: String {
        if let url = URL(string: repo.htmlURL), url.pathComponents.count >= 2 {
            return url.pathComponents[1]
        }
        return repo.account?.username ?? ""
    }

    private var currentPath: String {
        pathStack.last?.path ?? ""
    }

    private var navigationTitle: String {
        pathStack.last?.name ?? repo.name
    }

    var body: some View {
        NavigationStack {
            Group {
                if repo.isLocal {
                    localRepoIconView
                } else if isLoading && items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage, items.isEmpty {
                    errorStateView(error)
                } else {
                    fileListView
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if pathStack.isEmpty {
                        Button("cancel_button") { dismiss() }
                    } else {
                        Button {
                            navigateUp()
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "chevron.left")
                                    .fontWeight(.semibold)
                                Text("back_button")
                            }
                        }
                    }
                }
                if repo.logoURL != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .destructive) {
                            repo.logoURL = nil
                            dismiss()
                        } label: {
                            Text("icon_remove_button")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .task {
                await loadToken()
                guard !repo.isLocal else { return }
                await loadContents(path: "")
            }
        }
        .presentationDetents([.medium, .large])
        .frame(idealWidth: 540)
    }

    // MARK: - File List

    private var fileListView: some View {
        List {
            // Current icon preview
            if let logoURL = repo.logoURL, let url = URL(string: logoURL) {
                Section("icon_current_header") {
                    HStack {
                        Spacer()
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fit)
                            default:
                                Image(systemName: "photo")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }

            let folders = items.filter { $0.type == "dir" }
            let images = items.filter { $0.isImage }

            if !folders.isEmpty {
                Section("browser_folders_header") {
                    ForEach(folders) { item in
                        Button {
                            Task { await navigateInto(item) }
                        } label: {
                            Label(item.name, systemImage: "folder.fill")
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }

            if !images.isEmpty {
                Section("browser_images_header") {
                    ForEach(images) { item in
                        Button {
                            selectImage(item)
                        } label: {
                            HStack(spacing: 12) {
                                Group {
                                    if let urlStr = item.downloadUrl, let url = URL(string: urlStr) {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .success(let image):
                                                image.resizable().aspectRatio(contentMode: .fill)
                                            default:
                                                Image(systemName: "photo")
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    } else {
                                        Image(systemName: "photo").foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                Text(item.name)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Spacer()

                                if repo.logoURL == item.downloadUrl {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.purple)
                                }
                            }
                        }
                    }
                }
            }

            if folders.isEmpty && images.isEmpty && !isLoading {
                Section {
                    Text("browser_empty_folder")
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if isLoading {
                ProgressView()
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Local Repo Photo Picker

    private var localRepoIconView: some View {
        List {
            if let logoURL = repo.logoURL, let url = URL(string: logoURL) {
                Section("icon_current_header") {
                    HStack {
                        Spacer()
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fit)
                            default:
                                Image(systemName: "photo")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                PhotosPicker(
                    selection: $photoItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("local_icon_pick_photo", systemImage: "photo.on.rectangle")
                        .foregroundStyle(.primary)
                }

                if isSavingPhoto {
                    HStack {
                        Text("local_icon_saving")
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                }
            } footer: {
                Text("local_icon_footer")
            }
        }
        .listStyle(.insetGrouped)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await saveLocalPhoto(newItem) }
        }
    }

    private func errorStateView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("retry_button") {
                Task { await loadContents(path: currentPath) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Navigation

    private func navigateInto(_ item: RepoContentItem) async {
        pathStack.append(item)
        await loadContents(path: item.path)
    }

    private func navigateUp() {
        pathStack.removeLast()
        let path = pathStack.last?.path ?? ""
        Task { await loadContents(path: path) }
    }

    private func selectImage(_ item: RepoContentItem) {
        guard let downloadUrl = item.downloadUrl else { return }
        repo.logoURL = downloadUrl
        ToastManager.shared.show(String(localized: "icon_configured_toast"), style: .success)
        dismiss()
    }

    // MARK: - Local Photo Save

    private func saveLocalPhoto(_ item: PhotosPickerItem) async {
        isSavingPhoto = true
        defer { isSavingPhoto = false }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data),
              let jpegData = uiImage.jpegData(compressionQuality: 0.8)
        else { return }

        let filename = UUID().uuidString + ".jpg"
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(filename)
        try? jpegData.write(to: fileURL)

        repo.logoURL = fileURL.absoluteString
        ToastManager.shared.show(String(localized: "icon_configured_toast"), style: .success)
        dismiss()
    }

    // MARK: - Data Loading

    private func loadToken() async {
        guard let account = repo.account else { return }
        token = try? await KeychainManager.shared.retrieveToken(for: account.tokenKey)
    }

    private func loadContents(path: String) async {
        guard let token, !owner.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            let raw = try await GitHubService.shared.fetchContents(
                owner: owner, repo: repo.name, path: path, token: token)
            items = raw.sorted { lhs, rhs in
                if lhs.type != rhs.type { return lhs.type == "dir" }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Adaptive Repo List View (iPad/Mac - NavigationSplitView)

struct AdaptiveRepoListView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("isAuthenticated") private var isAuthenticated = false
    @AppStorage("isDemoMode") private var isDemoMode = false
    @Query(sort: \ProjectRepo.updatedAt, order: .reverse) private var repos: [ProjectRepo]
    @Query private var accounts: [GitHubAccount]
    @Query private var feedbackIssues: [FeedbackIssue]

    @State private var isLoading = false
    @State private var searchText = ""
    @State private var activeFilter: RepoFilter = .all
    @State private var selectedAccount: GitHubAccount?
    @State private var selectedRepo: ProjectRepo?
    @State private var filteredRepos: [ProjectRepo] = []
    @State private var showSettings = false
    @State private var showPaywall = false
    @State private var showAddLocalProject = false
    @State private var subscription = SubscriptionManager.shared
    @State private var repoToConfigureIcon: ProjectRepo?
    /// Set when a sync fails with an expired token, so the user can replace it without signing out.
    @State private var expiredTokenAccount: GitHubAccount?
    /// The repo whose folder the user is choosing.
    @State private var repoToFile: ProjectRepo?
    @AppStorage("lastTaskImportTimestamp") private var lastTaskImport: Double = 0
    @Environment(\.scenePhase) private var scenePhase

    /// Pulls in tasks an agent closed on GitHub, without having to open each board.
    ///
    /// Kept separate from `syncRepos`, which fetches the repo list and is rate-limited enough that
    /// it deliberately runs about once a week on iPhone — hanging this off it would leave the board
    /// just as stale. Throttled to two minutes so moving in and out of the list does not fire a
    /// request per repo every time; pull-to-refresh passes `force`.
    private func importAgentCompletedTasks(force: Bool = false) async {
        guard !isDemoMode else { return }
        let now = Date().timeIntervalSince1970
        guard force || now - lastTaskImport > 120 else { return }
        lastTaskImport = now

        let outcome = await TaskIssueSyncService.shared.syncIssuesEverywhere(
            repos: repos, context: context)

        // A pull-to-refresh always answers. Saying nothing when nothing moved is exactly what made
        // this impossible to tell apart from the feature not working at all.
        switch outcome {
        case .changed(let result):
            ToastManager.shared.show(
                TaskIssueSyncService.summary(for: result), style: .success)
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
    @Query(sort: \RepoFolder.orderIndex) private var folders: [RepoFolder]
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    private static let syncSuccessFeedback = UINotificationFeedbackGenerator()
    private static let deleteImpactFeedback = UIImpactFeedbackGenerator(style: .medium)

    @AppStorage("lastSyncTimestamp") private var lastSyncTimestamp: Double = 0
    private let autoSyncInterval: TimeInterval = 5 * 60

    @State private var isWaitingForCloudKit = false

    private var shouldAutoSync: Bool {
        repos.isEmpty || Date().timeIntervalSince1970 - lastSyncTimestamp > autoSyncInterval
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .searchable(text: $searchText, prompt: "search_placeholder")
        .refreshable {
            await syncRepos()
            await importAgentCompletedTasks(force: true)
        }
        .task {
            updateFilteredRepos()
            if repos.isEmpty {
                await waitForCloudKitThenSync()
            } else if shouldAutoSync {
                await syncRepos(silent: true)
            }
            await importAgentCompletedTasks()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await importAgentCompletedTasks() }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSNotification.Name("NSPersistentStoreRemoteChangeNotification"))
                .receive(on: RunLoop.main)
        ) { _ in
            isWaitingForCloudKit = false
            updateFilteredRepos()
        }
        .onChange(of: repos) { _, _ in updateFilteredRepos() }
        .onChange(of: activeFilter) { _, _ in updateFilteredRepos() }
        .onChange(of: selectedAccount) { _, _ in updateFilteredRepos() }
        .onChange(of: subscription.isPro) { _, _ in updateFilteredRepos() }
        // Debounce search so filtering doesn't fire on every keystroke
        .task(id: searchText) {
            if !searchText.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard !Task.isCancelled else { return }
            updateFilteredRepos()
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(item: $repoToConfigureIcon) { repo in
            RepoIconConfigSheet(repo: repo)
        }
        .sheet(item: $expiredTokenAccount) { account in
            ReauthSheet(account: account)
        }
        .sheet(item: $repoToFile) { repo in
            FolderPickerSheet(repo: repo)
        }
        .sheet(isPresented: $showAddLocalProject) {
            AddLocalProjectSheet()
                .environment(\.modelContext, context)
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncReposShortcut)) { _ in
            Task { await syncRepos() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsShortcut)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebarShortcut)) { _ in
            withAnimation {
                columnVisibility = (columnVisibility == .all) ? .detailOnly : .all
            }
        }
    }

    // MARK: - Sidebar

    private var sidebarAccountSection: some View {
        Section {
            Picker("accounts_filter", selection: $selectedAccount) {
                Text("all_accounts").tag(nil as GitHubAccount?)
                ForEach(accounts) { account in
                    Text(account.username).tag(account as GitHubAccount?)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var sidebarFilterSection: some View {
        Section {
            ForEach(RepoFilter.allCases) { filter in
                Button {
                    withAnimation { activeFilter = filter }
                } label: {
                    Label(filter.displayName, systemImage: filter.iconName)
                        .foregroundStyle(activeFilter == filter ? Color.accentColor : Color.primary)
                }
            }
        }
    }

    private struct RepoSection: Identifiable {
        let id: String
        let folder: RepoFolder?
        let repos: [ProjectRepo]
    }

    /// Same grouping as the phone list: folders first, loose repos last, empty folders omitted.
    private var repoSections: [RepoSection] {
        var sections = folders.compactMap { folder -> RepoSection? in
            let inFolder = filteredRepos.filter { $0.folder?.id == folder.id }
            guard !inFolder.isEmpty else { return nil }
            return RepoSection(id: folder.id.uuidString, folder: folder, repos: inFolder)
        }
        let unfiled = filteredRepos.filter { $0.folder == nil }
        if !unfiled.isEmpty {
            sections.append(RepoSection(id: "unfiled", folder: nil, repos: unfiled))
        }
        return sections
    }

    private func sidebarRepoRow(_ repo: ProjectRepo) -> some View {
        NavigationLink(value: repo) {
            RepoRow(
                repo: repo,
                isSelected: selectedRepo?.persistentModelID == repo.persistentModelID,
                unreadFeedback: repo.unreadFeedbackCount(in: feedbackIssues)
            )
        }
        .contextMenu {
            Button {
                repoToFile = repo
            } label: {
                Label("move_to_folder", systemImage: "folder")
            }
            // Mac has no swipe gesture, so anything offered only through swipeActions is simply
            // unreachable there. Configuring the icon was the one action that had no other route.
            Button {
                repoToConfigureIcon = repo
            } label: {
                Label("icon_configure_button", systemImage: "photo")
            }
            Button {
                Task { await toggleFavorite(for: repo) }
            } label: {
                Label(
                    repo.isFavorite ? "unfavorite" : "favorite",
                    systemImage: repo.isFavorite ? "star.slash" : "star.fill"
                )
            }
            Button {
                withAnimation {
                    repo.isArchived.toggle()
                    updateFilteredRepos()
                }
            } label: {
                Label(
                    repo.isArchived ? "unarchive" : "archive",
                    systemImage: repo.isArchived ? "tray.and.arrow.up" : "archivebox"
                )
            }
            if !repo.htmlURL.isEmpty {
                Button {
                    if let url = URL(string: repo.htmlURL) {
                        UIPasteboard.general.string = repo.htmlURL
                        _ = url
                    }
                } label: {
                    Label("copy_url", systemImage: "doc.on.doc")
                }
                Button {
                    if let url = URL(string: repo.htmlURL) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("open_in_github", systemImage: "arrow.up.forward.app")
                }
            }
            Divider()
            Button(role: .destructive) {
                withAnimation {
                    if selectedRepo?.persistentModelID == repo.persistentModelID {
                        selectedRepo = nil
                    }
                    context.delete(repo)
                }
            } label: {
                Label("delete_task", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await toggleFavorite(for: repo) }
            } label: {
                Label(
                    repo.isFavorite ? "unfavorite" : "favorite",
                    systemImage: repo.isFavorite ? "star.slash" : "star.fill"
                )
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                withAnimation {
                    if selectedRepo?.persistentModelID == repo.persistentModelID {
                        selectedRepo = nil
                    }
                    context.delete(repo)
                }
            } label: {
                Label("delete_task", systemImage: "trash")
            }
            Button {
                withAnimation {
                    repo.isArchived.toggle()
                    updateFilteredRepos()
                }
            } label: {
                Label(
                    repo.isArchived ? "unarchive" : "archive",
                    systemImage: repo.isArchived ? "tray.and.arrow.up" : "archivebox"
                )
            }
            .tint(.indigo)
        }
    }

    private var sidebar: some View {
        List(selection: $selectedRepo) {
            sidebarAccountSection
            // Renders nothing when there is nothing waiting.
            TodayEntryRow()
            sidebarFilterSection
            ForEach(repoSections) { section in
                Section {
                    ForEach(section.repos) { repo in
                        sidebarRepoRow(repo)
                    }
                } header: {
                    if let folder = section.folder {
                        Label {
                            Text(folder.name)
                        } icon: {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color(hex: folder.colorHex))
                        }
                    } else {
                        Text("repositories_title")
                    }
                }
            }
            Section {
                if !subscription.isPro && repos.count > subscription.maxFreeRepos {
                    Button { showPaywall = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill").foregroundStyle(.purple)
                            Text("repo_limit_banner_title").font(.subheadline.weight(.semibold))
                        }
                    }
                    .listRowBackground(Color.purple.opacity(0.08))
                }
            }
        }
        .macSidebarListStyle()
        .navigationTitle("repositories_title")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { accountMenuButton }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button { showSettings = true } label: {
                        Label("settings_label", systemImage: "gearshape")
                    }
                    Button { showAddLocalProject = true } label: {
                        Label("add_local_project_label", systemImage: "folder.badge.plus")
                    }
                    .labelStyle(.iconOnly)
                    syncButton
                }
            }
        }
        .overlay {
            if isWaitingForCloudKit || (repos.isEmpty && isLoading) {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("icloud_syncing_message")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if repos.isEmpty {
                ContentUnavailableView {
                    Label("no_repos_title", systemImage: "tray")
                } actions: {
                    Button("sync_button") { Task { await syncRepos() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if filteredRepos.isEmpty {
                ContentUnavailableView {
                    Label("no_results_title", systemImage: "magnifyingglass")
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let selectedRepo {
            KanbanView(project: selectedRepo)
        } else {
            ContentUnavailableView {
                Label("select_repo_prompt", systemImage: "sidebar.left")
            } description: {
                Text("select_repo_description")
            }
        }
    }

    // MARK: - Components

    private var accountMenuButton: some View {
        Menu {
            if !subscription.isPro {
                Button {
                    showPaywall = true
                } label: {
                    Label("upgrade_to_pro_button", systemImage: "crown")
                }
            }
            Button(role: .destructive, action: logout) {
                Label("sign_out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Group {
                if subscription.isPro {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.purple)
                } else {
                    Image(systemName: "person.2.circle")
                }
            }
            .font(.title3)
        }
    }

    private var syncButton: some View {
        Button {
            Task { await syncRepos() }
        } label: {
            if isLoading {
                ProgressView()
            } else {
                Label("sync_repos_label", systemImage: "arrow.trianglehead.2.clockwise")
                    .labelStyle(.iconOnly)
            }
        }
        .disabled(isLoading)
    }

    // MARK: - CloudKit Wait

    private func waitForCloudKitThenSync() async {
        let status = try? await CKContainer.default().accountStatus()
        guard status == .available else {
            await syncRepos()
            return
        }
        isWaitingForCloudKit = true
        let deadline = Date().addingTimeInterval(8)
        while repos.isEmpty && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(400))
        }
        isWaitingForCloudKit = false
        await syncRepos()
    }

    // MARK: - Logic (shared with RepoListView)

    private func updateFilteredRepos() {
        var result = repos
        switch activeFilter {
        case .all: result = result.filter { !$0.isArchived }
        case .favorites: result = result.filter { $0.isFavorite && !$0.isArchived }
        case .archived: result = result.filter { $0.isArchived }
        }
        if let account = selectedAccount {
            result = result.filter { $0.account?.id == account.id }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedStandardContains(searchText)
                    || $0.repoDescription.localizedStandardContains(searchText)
            }
        }
        var sorted = result.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return lhs.updatedAt > rhs.updatedAt
        }
        if !subscription.isPro && activeFilter == .all {
            let limit = subscription.maxFreeRepos
            if sorted.count > limit {
                let favorites = Array(sorted.filter { $0.isFavorite }.prefix(limit))
                let slotsForNonFav = max(0, limit - favorites.count)
                let nonFavorites = sorted.filter { !$0.isFavorite }
                sorted = favorites + Array(nonFavorites.prefix(slotsForNonFav))
            }
        }
        withAnimation(.smooth(duration: 0.35)) {
            filteredRepos = sorted
        }
    }

    private func toggleFavorite(for repo: ProjectRepo) async {
        let wasStarred = repo.isFavorite
        repo.isFavorite.toggle()
        updateFilteredRepos()
        guard let account = repo.account else { return }
        do {
            if let token = try await KeychainManager.shared.retrieveToken(for: account.tokenKey) {
                if repo.isFavorite {
                    try await GitHubService.shared.starRepo(owner: account.username, repo: repo.name, token: token)
                } else {
                    try await GitHubService.shared.unstarRepo(owner: account.username, repo: repo.name, token: token)
                }
            }
        } catch {
            repo.isFavorite = wasStarred
            updateFilteredRepos()
            ToastManager.shared.show(String(localized: "github_sync_error"), style: .error)
        }
    }

    private func syncRepos(silent: Bool = false) async {
        guard !isDemoMode else { return }
        // Reentrancy guard: pull-to-refresh, the Cmd+R shortcut and .onAppear can all fire this
        // independently. Two overlapping runs each fetch the repo list before either has saved,
        // both see the same remote repo as new, and each inserts its own duplicate.
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        guard !accounts.isEmpty else { return }
        do {
            for account in accounts {
                if let token = try await KeychainManager.shared.retrieveToken(for: account.tokenKey) {
                    try await GitHubService.shared.syncRepos(account: account, token: token, into: context)
                }
            }
            lastSyncTimestamp = Date().timeIntervalSince1970
            if !silent && !repos.isEmpty {
                ToastManager.shared.show(String(localized: "repos_synced_toast"), style: .success)
                Self.syncSuccessFeedback.notificationOccurred(.success)
            }
        } catch GitHubError.invalidToken {
            // An expired token is not a transient failure: every later sync fails identically, and
            // the only way to enter a new one was signing out — which deletes the local repos and
            // their tasks. Offer to replace it in place instead. Shown even on a silent refresh,
            // because otherwise a background sync would keep failing with nothing to see.
            expiredTokenAccount = selectedAccount ?? accounts.first { $0.username != "demo-user" }
        } catch {
            if !silent {
                ToastManager.shared.show(error.localizedDescription, style: .error)
            }
        }
    }

    private func logout() {
        Task {
            if isDemoMode {
                try? context.delete(model: GitHubAccount.self)
                try? context.delete(model: ProjectRepo.self)
                isDemoMode = false
                SubscriptionManager.shared.isDemoMode = false
            } else {
                try? context.delete(model: GitHubAccount.self)
                // Repos must go with the account. `GitHubAccount.repos` is `.nullify`, so deleting
                // only the account left repos behind with `account == nil`; the per-account filter
                // never matches those, so they stayed visible under "All accounts" to whoever
                // signed in next.
                try? context.delete(model: ProjectRepo.self)
                try? await KeychainManager.shared.deleteToken()
            }
            SubscriptionManager.shared.isMockPro = false
            lastSyncTimestamp = 0
            selectedRepo = nil
            withAnimation { isAuthenticated = false }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ProjectRepo.self, TaskItem.self], inMemory: true)
}
