import Foundation
import SwiftData
import SwiftUI

// MARK: - Card vocabulary

/// The folder a repo is filed in, as the home needs it for a section header.
struct HomeFolderInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let colorHex: String
    let orderIndex: Int
}

/// A pending task shown inline on the featured card.
struct HomeTaskPreview: Identifiable, Hashable {
    let id: UUID
    let title: String
}

/// The numbers in the strip under the title. Alerts and unpublished tasks only show when they
/// are not zero: a quiet app stays quiet.
struct HomeStats: Hashable {
    var totalRepos: Int
    var pendingTasks: Int
    var alerts = 0
    var unpublished = 0
}

extension HomeStats {
    init(cards: [HomeRepoCardData]) {
        self.init(
            totalRepos: cards.count,
            pendingTasks: cards.reduce(0) { $0 + $1.tasksPending },
            alerts: cards.reduce(0) { $0 + $1.alerts },
            unpublished: cards.reduce(0) { $0 + $1.unpublished }
        )
    }
}

// MARK: - Card data

/// Everything a repo card draws, flattened and value-typed.
///
/// `HomeView` never touches SwiftData: it renders these. That is what lets the same screen show
/// mock data in a preview and real repos in the app. What the model knows comes from
/// `ProjectRepo`; what only GitHub knows (pull requests, release, CI, last push, visibility)
/// comes from `RepoActivity` and is optional, so a card without it simply says less.
struct HomeRepoCardData: Identifiable, Hashable {
    let id: String
    var name: String
    var owner: String?
    var description = ""
    var isFavorite = false
    var isArchived = false
    var isPrivate = false
    /// The hero card at the top: larger logo and title, glow, and the task preview.
    var isFeatured = false
    /// Archived, or nothing pushed in six months. The only lifecycle badge the card derives,
    /// because it is the only lifecycle fact GitHub actually knows.
    var isInactive = false
    var folder: HomeFolderInfo?
    var logoURL: URL?
    /// An image from the asset catalog, for bundled logos and previews.
    var logoAssetName: String?
    var ownerAvatarURL: URL?
    var language: String?
    var stars = 0
    /// Open pull requests, when the activity cache has an answer. Shown only when non-zero.
    var pullRequests: Int?
    var isBuildFailing = false
    /// Tag of the latest GitHub release, if the repo publishes any.
    var version: String?
    /// Unread feedback reports.
    var alerts = 0
    /// Tasks that should be GitHub issues and are not yet.
    var unpublished = 0
    /// Issue sync switched itself off after a permission error.
    var isSyncDisabled = false
    var tasksTotal = 0
    var tasksPending = 0
    var taskPreview: [HomeTaskPreview] = []
    /// Last push to GitHub when known; `lastActivity` is the fallback.
    var lastPush: Date?
    var lastActivity: Date = .now

    /// Deterministic monogram colors for a repo without a logo. Derived from the name, not
    /// `hashValue`, so a repo keeps its color between launches.
    var monogramColors: [Color] {
        let seed = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let hue = Double(seed % 360) / 360
        return [
            Color(hue: hue, saturation: 0.55, brightness: 0.75),
            Color(hue: (hue + 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.7, brightness: 0.45)
        ]
    }
}

// MARK: - From SwiftData

extension ProjectRepo {
    /// Stable identity for the card built from this repo. Two local projects can share a name
    /// and a `repoID` of zero, so neither works as a `ForEach` id.
    var homeCardID: String { String(describing: persistentModelID) }
}

extension HomeRepoCardData {
    /// Six months without a push reads as inactive.
    static let inactiveAfter: TimeInterval = 180 * 24 * 60 * 60

    /// Builds a card from a stored repo plus whatever the activity cache knows about it.
    ///
    /// Pending tasks follow the board's own definition of done (`ProjectRepo.doneColumn`) and
    /// skip ideas, the same rules the issue sync applies — a card that disagreed with the board
    /// about how much is left would be worse than no number at all. Orphan tasks (no column)
    /// are not counted either; `OrphanTaskRepair` reattaches them.
    init(repo: ProjectRepo, unreadFeedback: Int = 0, activity: RepoActivity? = nil, now: Date = .now) {
        let tasks = (repo.tasks ?? []).sorted { $0.orderIndex < $1.orderIndex }
        let doneID = repo.doneColumn?.id
        let counted = tasks.filter { task in
            guard task.column != nil, !repo.isIdea(task) else { return false }
            return true
        }
        let pending = counted.filter { $0.column?.id != doneID }

        let full = repo.fullName
        let owner: String? = full.contains("/") ? String(full.prefix { $0 != "/" }) : nil

        let lastPush = activity?.pushedAt
        let quiet = lastPush.map { now.timeIntervalSince($0) > Self.inactiveAfter } ?? false

        self.init(
            id: repo.homeCardID,
            name: repo.name,
            owner: owner ?? repo.account?.username,
            description: repo.repoDescription,
            isFavorite: repo.isFavorite,
            isArchived: repo.isArchived,
            isPrivate: activity?.isPrivate ?? false,
            isInactive: repo.isArchived || quiet,
            folder: repo.folder.map {
                HomeFolderInfo(id: $0.id.uuidString, name: $0.name, colorHex: $0.colorHex, orderIndex: $0.orderIndex)
            },
            logoURL: repo.logoURL.flatMap(URL.init(string:)),
            ownerAvatarURL: repo.account?.avatarURL.flatMap(URL.init(string:)),
            language: repo.language,
            stars: repo.stargazersCount,
            pullRequests: activity?.openPullRequests,
            isBuildFailing: activity?.isBuildFailing ?? false,
            version: activity?.latestReleaseTag,
            alerts: unreadFeedback,
            unpublished: tasks.filter(\.needsIssueSync).count,
            isSyncDisabled: repo.syncTasksDisabledReason != nil,
            tasksTotal: counted.count,
            tasksPending: pending.count,
            taskPreview: pending.prefix(3).map { HomeTaskPreview(id: $0.id, title: $0.content) },
            lastPush: lastPush,
            lastActivity: repo.updatedAt
        )
    }
}
