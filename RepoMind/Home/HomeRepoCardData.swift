import Foundation
import SwiftData
import SwiftUI

// MARK: - Card vocabulary

/// Lifecycle stage of a project, shown as the badge on the trailing edge of its card.
enum HomeRepoStatus: String, CaseIterable, Identifiable {
    case live
    case stable
    case inDevelopment
    case beta
    case maintenance
    case inactive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: String(localized: "home_status_live")
        case .stable: String(localized: "home_status_stable")
        case .inDevelopment: String(localized: "home_status_in_development")
        case .beta: String(localized: "home_status_beta")
        case .maintenance: String(localized: "home_status_maintenance")
        case .inactive: String(localized: "home_status_inactive")
        }
    }

    var tint: Color {
        switch self {
        case .live: HomeTheme.success
        case .stable: HomeTheme.info
        case .inDevelopment: HomeTheme.accent
        case .beta, .maintenance: HomeTheme.warning
        case .inactive: HomeTheme.textSecondary
        }
    }
}

/// Outcome of the last CI run, worded like GitHub's own badge.
enum HomeBuildStatus: String {
    case passing
    case failing

    var title: String {
        switch self {
        case .passing: String(localized: "home_build_passing")
        case .failing: String(localized: "home_build_failing")
        }
    }

    var tint: Color { self == .passing ? HomeTheme.success : HomeTheme.danger }
    var symbol: String { self == .passing ? "checkmark.circle.fill" : "xmark.circle.fill" }
}

/// One language of a repo and the fraction of its code written in it.
struct HomeLanguageShare: Identifiable, Hashable {
    let name: String
    /// `0...1`. A repo with a single known language has `1`.
    let share: Double

    var id: String { name }
}

/// A task shown inline on the card, as a checklist row.
struct HomeTaskPreview: Identifiable, Hashable {
    let id: UUID
    let title: String
    let isDone: Bool
}

struct HomeCommitInfo: Hashable {
    let message: String
    let author: String
    let date: Date
}

/// The numbers in the strip under the title. Optional ones are left out of the strip entirely
/// when `nil`, so a source that cannot supply them shows nothing rather than a zero.
struct HomeStats: Hashable {
    var totalRepos: Int
    var commitsToday: Int?
    var alerts: Int?
    var pendingTasks: Int
}

// MARK: - Card data

/// Everything a repo card draws, flattened and value-typed.
///
/// `HomeView` never touches SwiftData: it renders these. That is what lets the same screen show
/// mock data in a preview, real repos in the app, and later whatever GitHub starts providing
/// (commit activity, pull requests, CI) without the view changing. Fields the app cannot fill
/// yet are optional and simply hide their row.
struct HomeRepoCardData: Identifiable, Hashable {
    let id: String
    var name: String
    var owner: String?
    var description: String = ""
    var isFavorite = false
    /// The user's own app. Gets the "Your app" tag and the accent border.
    var isOwnApp = false
    /// The hero card at the top: larger logo, larger title, glow.
    var isFeatured = false
    var status: HomeRepoStatus?
    var version: String?
    var branch: String?
    var logoURL: URL?
    /// An image from the asset catalog, for bundled logos and previews.
    var logoAssetName: String?
    var ownerAvatarURL: URL?
    var languages: [HomeLanguageShare] = []
    var stars = 0
    var openIssues: Int?
    var pullRequests: Int?
    /// Unread feedback reports, or anything else that needs the user's eyes.
    var alerts: Int?
    var collaborators: Int?
    var build: HomeBuildStatus?
    var tasksTotal = 0
    var tasksPending = 0
    var taskPreview: [HomeTaskPreview] = []
    var lastActivity: Date = .now
    var lastCommit: HomeCommitInfo?
    /// Commits per day, oldest first. Seven entries for the sparkline.
    var commitsLast7Days: [Int]?

    /// Share of tasks done, `nil` when there are no tasks to measure.
    var progress: Double? {
        guard tasksTotal > 0 else { return nil }
        return Double(tasksTotal - tasksPending) / Double(tasksTotal)
    }

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
    /// Builds a card from a stored repo, using only what the app knows today.
    ///
    /// Pending tasks follow the board's own definition of done (`ProjectRepo.doneColumn`) and
    /// skip ideas, the same rules the issue sync applies — a card that disagreed with the board
    /// about how much is left would be worse than no number at all. Orphan tasks (no column)
    /// are not counted either; `OrphanTaskRepair` reattaches them.
    init(repo: ProjectRepo, unreadFeedback: Int = 0) {
        let tasks = (repo.tasks ?? []).sorted { $0.orderIndex < $1.orderIndex }
        let doneID = repo.doneColumn?.id
        let counted = tasks.filter { task in
            guard task.column != nil, !repo.isIdea(task) else { return false }
            return true
        }
        let pending = counted.filter { $0.column?.id != doneID }

        let full = repo.fullName
        let owner: String? = full.contains("/") ? String(full.prefix { $0 != "/" }) : nil

        let status: HomeRepoStatus?
        if repo.isArchived {
            status = .inactive
        } else if repo.isLocal {
            status = .inDevelopment
        } else {
            status = nil
        }

        self.init(
            id: repo.homeCardID,
            name: repo.name,
            owner: owner ?? repo.account?.username,
            description: repo.repoDescription,
            isFavorite: repo.isFavorite,
            status: status,
            logoURL: repo.logoURL.flatMap(URL.init(string:)),
            ownerAvatarURL: repo.account?.avatarURL.flatMap(URL.init(string:)),
            languages: repo.language.map { [HomeLanguageShare(name: $0, share: 1)] } ?? [],
            stars: repo.stargazersCount,
            alerts: unreadFeedback > 0 ? unreadFeedback : nil,
            tasksTotal: counted.count,
            tasksPending: pending.count,
            taskPreview: pending.prefix(3).map {
                HomeTaskPreview(id: $0.id, title: $0.content, isDone: false)
            },
            lastActivity: repo.updatedAt
        )
    }
}
