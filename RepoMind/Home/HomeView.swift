import Foundation
import SwiftUI

// MARK: - Home

/// The redesigned home screen: dense cards on pure black, one accent, hairlines instead of
/// shadows.
///
/// Pure presentation. It takes card data and a few callbacks and owns only its own UI state
/// (filter, search, tab), so the same view renders `HomeMockData` in a preview and real repos
/// through `HomeLiveView`. Colors follow the system appearance via the `Home*` colorsets; the
/// dark one is the design, the light one is derived from it.
struct HomeView: View {
    var accountName: String?
    let stats: HomeStats
    let repos: [HomeRepoCardData]
    var onSelectRepo: (HomeRepoCardData) -> Void = { _ in }
    var onFilter: () -> Void = {}
    var onAdd: () -> Void = {}
    var onNotifications: () -> Void = {}

    @State private var filter: HomeFilter = .all
    @State private var tab: HomeTab = .repos
    @State private var isSearching = false
    @State private var searchText = ""

    private var query: String { searchText.trimmingCharacters(in: .whitespaces) }

    private var visibleRepos: [HomeRepoCardData] {
        let filtered = filter.apply(to: repos)
        guard isSearching, !query.isEmpty else { return filtered }
        return filtered.filter {
            $0.name.localizedStandardContains(query) || $0.description.localizedStandardContains(query)
        }
    }

    var body: some View {
        ZStack {
            HomeTheme.background
                .ignoresSafeArea()
            switch tab {
            case .repos:
                reposTab
            case .tasks, .profile, .settings:
                comingSoon
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HomeTabBar(selection: $tab)
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
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Repos

    private var reposTab: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HomeHeaderView(
                    accountName: accountName,
                    stats: stats,
                    filter: $filter,
                    isSearching: $isSearching,
                    searchText: $searchText,
                    onFilter: onFilter,
                    onAdd: onAdd,
                    onNotifications: onNotifications
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)

                if visibleRepos.isEmpty {
                    emptyState
                } else {
                    ForEach(visibleRepos) { repo in
                        Button {
                            onSelectRepo(repo)
                        } label: {
                            HomeRepoCardView(repo: repo)
                        }
                        .buttonStyle(HomeCardButtonStyle())
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
            }
            .padding(.horizontal, HomeTheme.gutter)
            .padding(.top, 6)
            .padding(.bottom, 12)
            .animation(.smooth(duration: 0.3), value: visibleRepos)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            if isSearching && !query.isEmpty {
                Label("no_results_title", systemImage: "magnifyingglass")
            } else {
                Label("no_repos_title", systemImage: "tray")
            }
        } description: {
            if isSearching && !query.isEmpty {
                Text("no_results_message")
            } else {
                Text("connect_account_prompt")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: Other tabs

    private var comingSoon: some View {
        ContentUnavailableView {
            Label(tab.label, systemImage: tab.symbol)
        } description: {
            Text("home_tab_coming_soon")
        }
    }
}

// MARK: - Previews

#Preview("Home · dark") {
    HomeView(accountName: HomeMockData.accountName, stats: HomeMockData.stats, repos: HomeMockData.repos)
        .preferredColorScheme(.dark)
}

#Preview("Home · light") {
    HomeView(accountName: HomeMockData.accountName, stats: HomeMockData.stats, repos: HomeMockData.repos)
        .preferredColorScheme(.light)
}

#Preview("Home · empty") {
    HomeView(accountName: nil, stats: HomeStats(totalRepos: 0, pendingTasks: 0), repos: [])
        .preferredColorScheme(.dark)
}
