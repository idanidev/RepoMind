import Foundation
import SwiftUI

// MARK: - Actions

/// Everything the home can ask its host to do. Defaults are no-ops, so a preview needs nothing.
struct HomeActions {
    var selectRepo: (HomeRepoCardData) -> Void = { _ in }
    var toggleFavorite: (HomeRepoCardData) -> Void = { _ in }
    var toggleArchive: (HomeRepoCardData) -> Void = { _ in }
    var delete: (HomeRepoCardData) -> Void = { _ in }
    var moveToFolder: (HomeRepoCardData) -> Void = { _ in }
    var configureIcon: (HomeRepoCardData) -> Void = { _ in }
    var openOnGitHub: (HomeRepoCardData) -> Void = { _ in }
    var selectAccount: (String?) -> Void = { _ in }
    var upgrade: () -> Void = {}
    var signOut: () -> Void = {}
    var add: () -> Void = {}
    var notifications: () -> Void = {}
    var refresh: () async -> Void = {}
}

// MARK: - Home

/// The repositories tab of the redesigned home: dense cards on pure black, one accent, hairlines
/// instead of shadows.
///
/// Pure presentation. It takes card data and `HomeActions` and owns only its own UI state
/// (filter, search, the delete confirmation), so the same view renders `HomeMockData` in a
/// preview and real repos through `HomeLiveView`, which also provides the tab bar around it.
struct HomeView: View {
    var account = HomeAccountMenuData()
    let stats: HomeStats
    let repos: [HomeRepoCardData]
    /// `nil` for Pro. A free account sees at most this many repos per filter, favorites first,
    /// and a banner says how many are hidden — the same gate `RepoListView` applies.
    var repoLimit: Int?
    /// Typed in the search field at the bottom; empty means no search.
    var searchText = ""
    var actions = HomeActions()

    @State private var filter: HomeFilter = .all
    @State private var repoToDelete: HomeRepoCardData?

    private var query: String { searchText.trimmingCharacters(in: .whitespaces) }

    /// Filter chip and search applied, before the free-tier gate.
    private var matchingRepos: [HomeRepoCardData] {
        let filtered = filter.apply(to: repos)
        guard !query.isEmpty else { return filtered }
        return filtered.filter {
            $0.name.localizedStandardContains(query) || $0.description.localizedStandardContains(query)
        }
    }

    private var visibleRepos: [HomeRepoCardData] {
        SubscriptionManager.visible(matchingRepos, limit: repoLimit, isFavorite: \.isFavorite)
    }

    private var hiddenCount: Int { matchingRepos.count - visibleRepos.count }

    private struct HomeSection: Identifiable {
        let id: String
        let folder: HomeFolderInfo?
        let repos: [HomeRepoCardData]
    }

    /// Folders first, in their own order, loose repos last — the grouping the classic list uses.
    /// A folder none of the visible repos belong to has no header: an empty section is noise.
    private var sections: [HomeSection] {
        var order: [HomeFolderInfo] = []
        var filed: [String: [HomeRepoCardData]] = [:]
        var loose: [HomeRepoCardData] = []
        for repo in visibleRepos {
            guard let folder = repo.folder else {
                loose.append(repo)
                continue
            }
            if filed[folder.id] == nil {
                order.append(folder)
            }
            filed[folder.id, default: []].append(repo)
        }
        var sections = order
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { HomeSection(id: $0.id, folder: $0, repos: filed[$0.id] ?? []) }
        if !loose.isEmpty {
            sections.append(HomeSection(id: "loose", folder: nil, repos: loose))
        }
        return sections
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HomeHeaderView(
                    account: account,
                    stats: stats,
                    filter: $filter,
                    onSelectAccount: actions.selectAccount,
                    onUpgrade: actions.upgrade,
                    onSignOut: actions.signOut,
                    onAdd: actions.add,
                    onNotifications: actions.notifications
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)

                if visibleRepos.isEmpty {
                    emptyState
                } else {
                    ForEach(sections) { section in
                        if let folder = section.folder {
                            folderHeader(folder)
                        }
                        ForEach(section.repos) { repo in
                            card(repo)
                        }
                    }
                }

                if hiddenCount > 0 {
                    limitBanner
                }
            }
            .padding(.horizontal, HomeTheme.gutter)
            .padding(.top, 6)
            .padding(.bottom, 12)
            .animation(.smooth(duration: 0.3), value: visibleRepos)
        }
        .refreshable { await actions.refresh() }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .confirmationDialog(
            "home_delete_repo_title",
            isPresented: deleteConfirmation,
            titleVisibility: .visible,
            presenting: repoToDelete
        ) { repo in
            Button("delete_task", role: .destructive) { actions.delete(repo) }
            Button("cancel_button", role: .cancel) {}
        } message: { repo in
            Text("home_delete_repo_message \(repo.name)")
        }
    }

    private var deleteConfirmation: Binding<Bool> {
        Binding(get: { repoToDelete != nil }, set: { if !$0 { repoToDelete = nil } })
    }

    // MARK: Rows

    private func card(_ repo: HomeRepoCardData) -> some View {
        Button {
            actions.selectRepo(repo)
        } label: {
            HomeRepoCardView(repo: repo)
        }
        .buttonStyle(HomeCardButtonStyle())
        .contextMenu { contextMenu(for: repo) }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    /// The classic list's swipe actions, as a long-press menu: cards here are not list rows.
    @ViewBuilder
    private func contextMenu(for repo: HomeRepoCardData) -> some View {
        Button {
            actions.toggleFavorite(repo)
        } label: {
            Label(
                repo.isFavorite ? "unfavorite" : "favorite",
                systemImage: repo.isFavorite ? "star.slash" : "star.fill"
            )
        }
        Button {
            actions.moveToFolder(repo)
        } label: {
            Label("move_to_folder", systemImage: "folder")
        }
        Button {
            actions.configureIcon(repo)
        } label: {
            Label("icon_configure_button", systemImage: "photo.badge.plus")
        }
        if repo.owner != nil {
            Button {
                actions.openOnGitHub(repo)
            } label: {
                Label("home_open_on_github", systemImage: "arrow.up.right.square")
            }
        }
        Divider()
        Button {
            actions.toggleArchive(repo)
        } label: {
            Label(
                repo.isArchived ? "unarchive" : "archive",
                systemImage: repo.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }
        Button(role: .destructive) {
            repoToDelete = repo
        } label: {
            Label("delete_task", systemImage: "trash")
        }
    }

    private func folderHeader(_ folder: HomeFolderInfo) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: folder.colorHex))
                .frame(width: 6, height: 6)
            Text(folder.name.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(HomeTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.top, 4)
        .padding(.leading, 2)
        .accessibilityAddTraits(.isHeader)
    }

    /// Shown to a free account with more repos than the tier allows. Tapping opens the paywall.
    private var limitBanner: some View {
        Button(action: actions.upgrade) {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .font(.title3)
                    .foregroundStyle(HomeTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("repo_limit_banner_title")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeTheme.textPrimary)
                    Text(String(format: String(localized: "repo_limit_banner_subtitle"), hiddenCount))
                        .font(.caption)
                        .foregroundStyle(HomeTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(HomeTheme.textSecondary)
            }
            .padding(HomeTheme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: HomeTheme.cardRadius, style: .continuous)
                    .fill(HomeTheme.accent.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: HomeTheme.cardRadius, style: .continuous)
                    .strokeBorder(HomeTheme.accent.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(HomeCardButtonStyle())
    }

    private var emptyState: some View {
        ContentUnavailableView {
            if !query.isEmpty {
                Label("no_results_title", systemImage: "magnifyingglass")
            } else if filter == .archived {
                Label("no_archived_title", systemImage: "archivebox")
            } else {
                Label("no_repos_title", systemImage: "tray")
            }
        } description: {
            if !query.isEmpty {
                Text("no_results_message")
            } else if filter == .archived {
                Text("no_archived_message")
            } else {
                Text("connect_account_prompt")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// MARK: - Previews

#Preview("Home · dark") {
    HomeView(
        account: HomeAccountMenuData(names: [HomeMockData.accountName], isPro: true),
        stats: HomeMockData.stats,
        repos: HomeMockData.repos
    )
    .background(HomeTheme.background)
    .preferredColorScheme(.dark)
}

#Preview("Home · free tier") {
    HomeView(
        account: HomeAccountMenuData(names: [HomeMockData.accountName]),
        stats: HomeMockData.stats,
        repos: HomeMockData.repos,
        repoLimit: 3
    )
    .background(HomeTheme.background)
    .preferredColorScheme(.dark)
}

#Preview("Home · empty") {
    HomeView(stats: HomeStats(totalRepos: 0, pendingTasks: 0), repos: [])
        .background(HomeTheme.background)
        .preferredColorScheme(.light)
}
