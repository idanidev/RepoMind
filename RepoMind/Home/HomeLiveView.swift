import SwiftData
import SwiftUI

/// Where the user can go from the home screen besides a board.
enum HomeRoute: Hashable {
    case today
}

// MARK: - Live home

/// The redesigned home fed from SwiftData.
///
/// `HomeView` knows nothing about models. This is the one place that turns `ProjectRepo` into
/// card data, applies the free-tier limit the same way `RepoListView` does, and pushes the board
/// when a card is tapped. Drop it in wherever `RepoListView()` is used to try the redesign.
struct HomeLiveView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ProjectRepo.updatedAt, order: .reverse) private var repos: [ProjectRepo]
    @Query private var accounts: [GitHubAccount]
    @Query private var feedbackIssues: [FeedbackIssue]

    @State private var subscription = SubscriptionManager.shared
    @State private var path = NavigationPath()
    @State private var showAddLocalProject = false

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                accountName: accountName,
                stats: stats,
                repos: cards,
                onSelectRepo: open,
                onAdd: { showAddLocalProject = true },
                onNotifications: { path.append(HomeRoute.today) }
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
            var card = HomeRepoCardData(repo: repo, unreadFeedback: unread[repo.fullName] ?? 0)
            card.isFeatured = index == 0
            return card
        }
    }

    private var stats: HomeStats {
        let cards = self.cards
        let alerts = cards.reduce(0) { $0 + ($1.alerts ?? 0) }
        return HomeStats(
            totalRepos: cards.count,
            commitsToday: nil,
            alerts: alerts,
            pendingTasks: cards.reduce(0) { $0 + $1.tasksPending }
        )
    }

    private func open(_ card: HomeRepoCardData) {
        guard let repo = visibleRepos.first(where: { $0.homeCardID == card.id }) else { return }
        path.append(repo)
    }
}
