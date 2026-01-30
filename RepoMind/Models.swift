import Foundation
import SwiftData

// MARK: - GitHub Account (Multi-Account Support)

@Model
final class GitHubAccount {
    var id: UUID
    var username: String
    var avatarURL: String?
    var tokenKey: String  // Key to retrieve token from Keychain
    var isPro: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \ProjectRepo.account)
    var repos: [ProjectRepo]? = []  // Optional for CloudKit

    init(username: String, avatarURL: String? = nil, tokenKey: String, isPro: Bool = false) {
        self.id = UUID()
        self.username = username
        self.avatarURL = avatarURL
        self.tokenKey = tokenKey
        self.isPro = isPro
    }
}

// MARK: - ProjectRepo (RepoEntity - CloudKit Ready)

@Model
final class ProjectRepo {
    @Attribute(.unique) var repoID: Int
    var name: String = ""
    var repoDescription: String = ""
    var updatedAt: Date = Date.now
    var htmlURL: String = ""
    var isFavorite: Bool = false
    var isArchived: Bool = false
    var language: String? = nil
    var stargazersCount: Int = 0

    // CloudKit Optimization: Optional relationship
    var account: GitHubAccount?

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.project)
    var tasks: [TaskItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \KanbanColumn.project)
    var columns: [KanbanColumn]? = []

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

// MARK: - Kanban Column (Dynamic & CloudKit)

@Model
final class KanbanColumn {
    var id: UUID
    var name: String = ""
    var orderIndex: Int = 0
    var isCollapsed: Bool = false
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.column)
    var tasks: [TaskItem]? = []

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

// MARK: - TaskItem (CloudKit Ready)

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var content: String = ""
    var createdAt: Date = Date.now
    var audioPath: String? = nil

    // Dynamic Status (String driven)
    var status: String = "todo"  // "brainstorming", "todo", "done", or custom

    var column: KanbanColumn?
    var project: ProjectRepo?

    init(
        content: String,
        status: String = "todo",  // Default status
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
