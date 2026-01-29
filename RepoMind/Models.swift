import Foundation
import SwiftData

// MARK: - Task Status

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case brainstorming
    case todo
    case done

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .brainstorming: "Brainstorming"
        case .todo: "To-Do"
        case .done: "Done"
        }
    }

    var iconName: String {
        switch self {
        case .brainstorming: "brain.head.profile"
        case .todo: "checklist"
        case .done: "checkmark.seal.fill"
        }
    }

    var sectionHeader: String {
        switch self {
        case .brainstorming: "Brainstorming"
        case .todo: "To-Do"
        case .done: "Done"
        }
    }

    var emptyMessage: String {
        switch self {
        case .brainstorming: "Sin ideas todavia... Usa el micro o pulsa +"
        case .todo: "Nada pendiente. Mueve tareas aqui."
        case .done: "Completa tareas para verlas aqui."
        }
    }

    var emptyIconName: String {
        switch self {
        case .brainstorming: "lightbulb"
        case .todo: "tray"
        case .done: "checkmark.circle"
        }
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
    var isFavorite: Bool = false
    var isArchived: Bool = false
    var language: String?
    var stargazersCount: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.project)
    var tasks: [TaskItem] = []

    @Relationship(deleteRule: .cascade, inverse: \KanbanColumn.project)
    var columns: [KanbanColumn] = []

    init(
        repoID: Int,
        name: String,
        repoDescription: String = "",
        updatedAt: Date = .now,
        htmlURL: String = "",
        isFavorite: Bool = false,
        isArchived: Bool = false,
        language: String? = nil,
        stargazersCount: Int = 0
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
    }
}

// MARK: - TaskItem

@Model
final class TaskItem {
    #Unique<TaskItem>([\.id])

    var id: UUID
    var content: String
    var createdAt: Date
    var audioPath: String?

    // Changing from Enum to Dynamic Column Relationship
    var column: KanbanColumn?

    // Deprecating/Removing strict enum dependence eventually
    // var status: TaskStatus

    var project: ProjectRepo?

    init(
        content: String,
        column: KanbanColumn? = nil,
        audioPath: String? = nil,
        project: ProjectRepo? = nil
    ) {
        self.id = UUID()
        self.content = content
        self.createdAt = .now
        self.audioPath = audioPath
        self.column = column
        self.project = project
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
    var tasks: [TaskItem] = []

    // Parent Project
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
