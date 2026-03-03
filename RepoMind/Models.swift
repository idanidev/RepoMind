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
    var audioPath: String?
    var imagePath: String?
    @Attribute(.externalStorage) var imageData: Data?
    var status: String = "todo"
    var orderIndex: Int = 0

    var column: KanbanColumn?
    var project: ProjectRepo?

    init(
        content: String,
        status: String = "todo",
        column: KanbanColumn? = nil,
        audioPath: String? = nil,
        imagePath: String? = nil,
        project: ProjectRepo? = nil,
        orderIndex: Int = 0
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
