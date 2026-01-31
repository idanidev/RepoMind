import Foundation
import SwiftData

// MARK: - GitHub Account (Multi-Account Support)

@Model
final class GitHubAccount {
    var id: UUID
    var username: String
    var avatarURL: String?
    var tokenKey: String
    var isPro: Bool

    @Relationship(deleteRule: .cascade, inverse: \ProjectRepo.account)
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
    @Attribute(.unique) var repoID: Int
    var name: String
    var repoDescription: String
    var updatedAt: Date
    var htmlURL: String
    var isFavorite: Bool
    var isArchived: Bool
    var language: String?
    var stargazersCount: Int

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
        language: String? = nil,
        stargazersCount: Int = 0,
        account: GitHubAccount? = nil
    ) {
        self.repoID = repoID
        self.name = name
        self.repoDescription = repoDescription
        self.updatedAt = updatedAt
        self.htmlURL = htmlURL
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.language = language
        self.stargazersCount = stargazersCount
        self.account = account
    }
}

// MARK: - Kanban Column

@Model
final class KanbanColumn {
    var id: UUID
    var name: String
    var orderIndex: Int
    var isCollapsed: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.column)
    var tasks: [TaskItem]?

    var project: ProjectRepo?

    init(
        name: String,
        orderIndex: Int,
        isCollapsed: Bool = false,
        project: ProjectRepo? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.orderIndex = orderIndex
        self.isCollapsed = isCollapsed
        self.createdAt = .now
        self.project = project
    }
}

// MARK: - TaskItem

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var content: String
    var createdAt: Date
    var audioPath: String?
    var status: String

    var column: KanbanColumn?
    var project: ProjectRepo?

    init(
        content: String,
        status: String = "todo",
        column: KanbanColumn? = nil,
        audioPath: String? = nil,
        project: ProjectRepo? = nil
    ) {
        self.id = UUID()
        self.content = content
        self.status = status
        self.createdAt = .now
        self.audioPath = audioPath
        self.column = column
        self.project = project
    }
}
