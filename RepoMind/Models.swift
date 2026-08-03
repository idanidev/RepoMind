import Foundation
import SwiftData

// MARK: - GitHub Account (Multi-Account Support)

@Model
final class GitHubAccount {
    var id: UUID = UUID()
    var username: String = ""
    var avatarURL: String?
    var tokenKey: String = ""
    var isPro: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \ProjectRepo.account)
    var repos: [ProjectRepo]?

    init(
        username: String,
        avatarURL: String? = nil,
        tokenKey: String,
        isPro: Bool = false
    ) {
        self.id = UUID()
        self.username = username
        self.avatarURL = avatarURL
        self.tokenKey = tokenKey
        self.isPro = isPro
    }
}

// MARK: - ProjectRepo

@Model
final class ProjectRepo {
    var repoID: Int = 0
    var name: String = ""
    var repoDescription: String = ""
    var updatedAt: Date = Date.now
    var htmlURL: String = ""
    var isFavorite: Bool = false
    var isArchived: Bool = false
    var isLocal: Bool = false
    var language: String?
    var stargazersCount: Int = 0
    var logoURL: String?
    /// Feature toggle: mirror this repo's Kanban tasks as GitHub Issues.
    var syncTasksToGitHub: Bool = false
    /// Set when a sync attempt fails with a permission/existence error (403/404/410),
    /// so the toggle auto-disables and the user is warned next time the board opens.
    var syncTasksDisabledReason: String?

    var account: GitHubAccount?

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.project)
    var tasks: [TaskItem]?

    @Relationship(deleteRule: .cascade, inverse: \KanbanColumn.project)
    var columns: [KanbanColumn]?

    init(
        repoID: Int,
        name: String,
        repoDescription: String = "",
        updatedAt: Date = .now,
        htmlURL: String = "",
        isFavorite: Bool = false,
        isArchived: Bool = false,
        isLocal: Bool = false,
        language: String? = nil,
        stargazersCount: Int = 0,
        logoURL: String? = nil,
        account: GitHubAccount? = nil
    ) {
        self.repoID = repoID
        self.name = name
        self.repoDescription = repoDescription
        self.updatedAt = updatedAt
        self.htmlURL = htmlURL
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.isLocal = isLocal
        self.language = language
        self.stargazersCount = stargazersCount
        self.logoURL = logoURL
        self.account = account
    }
}

extension ProjectRepo {
    /// `owner/name`, the way GitHub identifies a repository.
    ///
    /// Computed, not stored — the CloudKit schema is unaffected. This parsing existed in six
    /// places in two incompatible variants; the copy behind the unread-feedback badge omitted the
    /// fallback below, so a repo with no `htmlURL` produced a name that matched nothing and the
    /// badge silently read zero.
    var fullName: String {
        let owner = URL(string: htmlURL)?.pathComponents.first { $0 != "/" } ?? ""
        return owner.isEmpty ? name : "\(owner)/\(name)"
    }
}

// MARK: - Kanban Column

@Model
final class KanbanColumn {
    var id: UUID = UUID()
    var name: String = ""
    var orderIndex: Int = 0
    var isCollapsed: Bool = false
    var createdAt: Date = Date.now
    var colorHex: String = "#7C3AED"

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.column)
    var tasks: [TaskItem]?

    var project: ProjectRepo?

    init(
        name: String,
        orderIndex: Int,
        isCollapsed: Bool = false,
        colorHex: String? = nil,
        project: ProjectRepo? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.orderIndex = orderIndex
        self.isCollapsed = isCollapsed
        // Todas las columnas del mismo color púrpura
        self.colorHex = colorHex ?? "#7C3AED"
        self.createdAt = .now
        self.project = project
    }
}

// MARK: - TaskItem

@Model
final class TaskItem {
    var id: UUID = UUID()
    var content: String = ""
    var createdAt: Date = Date.now
    /// Unused: nothing ever writes this, so the voice-note badge it drove could never appear.
    /// Kept only because CloudKit does not allow removing a field once deployed to Production.
    var audioPath: String?
    var imagePath: String?
    @Attribute(.externalStorage) var imageData: Data?
    /// Redundant with `column`, and drifts out of sync with it — only the backup round-trip still
    /// reads it. Kept for the same CloudKit reason as `audioPath`; use `column` everywhere else.
    var status: String = "todo"
    var orderIndex: Int = 0
    /// GitHub issue number if this task is mirrored as an issue. Nil = not synced.
    var issueNumber: Int?
    /// Set when a GitHub sync operation fails (offline, expired token) so reconciliation retries later.
    var needsIssueSync: Bool = false

    var column: KanbanColumn?
    var project: ProjectRepo?

    init(
        content: String,
        status: String = "todo",
        column: KanbanColumn? = nil,
        audioPath: String? = nil,
        imagePath: String? = nil,
        project: ProjectRepo? = nil,
        orderIndex: Int = 0,
        issueNumber: Int? = nil,
        needsIssueSync: Bool = false
    ) {
        self.id = UUID()
        self.content = content
        self.status = status
        self.createdAt = .now
        self.audioPath = audioPath
        self.imagePath = imagePath
        self.column = column
        self.project = project
        self.orderIndex = orderIndex
        self.issueNumber = issueNumber
        self.needsIssueSync = needsIssueSync
    }
}

// MARK: - Feedback Issue

enum FeedbackSeverity: String, CaseIterable, Codable {
    case critical
    case minor
    case enhancement
    case general

    static func from(labels: [String]) -> FeedbackSeverity {
        let lower = Set(labels.map { $0.lowercased() })
        if lower.contains("bug:critical") { return .critical }
        if lower.contains("bug:minor") { return .minor }
        if lower.contains("enhancement") { return .enhancement }
        return .general
    }
}

@Model
final class FeedbackIssue {
    var id: UUID = UUID()
    /// GitHub issue number, unique per repo (NOT app-wide).
    var issueNumber: Int = 0
    /// `owner/repo` format — used to scope queries.
    var repoFullName: String = ""
    var title: String = ""
    var bodyText: String = ""
    var htmlURL: String = ""
    /// Raw severity string — back to enum via `severityEnum` (CloudKit can't store enums directly).
    var severityRaw: String = FeedbackSeverity.general.rawValue
    /// "open" or "closed".
    var state: String = "open"
    /// `email`, `app_store_review`, `github`, etc. — parsed from issue body.
    var source: String = "github"
    /// Star rating (1–5), nil if not a review.
    var rating: Int?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var isRead: Bool = false
    /// Hidden from main list until this date passes. Nil = visible.
    var snoozedUntil: Date?
    /// Persistent model id of TaskItem if user converted issue to a Kanban task.
    var convertedTaskColumnName: String?

    var severityEnum: FeedbackSeverity {
        FeedbackSeverity(rawValue: severityRaw) ?? .general
    }

    var isSnoozed: Bool {
        guard let until = snoozedUntil else { return false }
        return until > .now
    }

    init(
        issueNumber: Int,
        repoFullName: String,
        title: String,
        bodyText: String = "",
        htmlURL: String = "",
        severity: FeedbackSeverity = .general,
        state: String = "open",
        source: String = "github",
        rating: Int? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isRead: Bool = false,
        snoozedUntil: Date? = nil,
        convertedTaskColumnName: String? = nil
    ) {
        self.id = UUID()
        self.issueNumber = issueNumber
        self.repoFullName = repoFullName
        self.title = title
        self.bodyText = bodyText
        self.htmlURL = htmlURL
        self.severityRaw = severity.rawValue
        self.state = state
        self.source = source
        self.rating = rating
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isRead = isRead
        self.snoozedUntil = snoozedUntil
        self.convertedTaskColumnName = convertedTaskColumnName
    }
}

// MARK: - Color Extension for Hex

import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
