import Foundation

// MARK: - Mock data

/// The six repos of the design mock, for previews and for trying the screen without an account.
///
/// Repo names, descriptions and commit messages are data the way GitHub would supply them, so
/// they are deliberately not localized.
enum HomeMockData {
    static let accountName = "idanidev"

    static let stats = HomeStats(totalRepos: 6, commitsToday: 13, alerts: 4, pendingTasks: 8)

    static var repos: [HomeRepoCardData] {
        [focvs, inSync, repoMind, rentalManagerIOS, clarity, rentalManagerWeb]
    }

    static var focvs: HomeRepoCardData {
        HomeRepoCardData(
            id: "mock-focvs",
            name: "FOCVS",
            owner: accountName,
            description: "Temporizador de enfoque con sesiones suaves y un widget discreto",
            isFavorite: true,
            isFeatured: true,
            status: .live,
            version: "v1.2.0",
            branch: "main",
            languages: [HomeLanguageShare(name: "Swift", share: 1)],
            stars: 12,
            openIssues: 1,
            pullRequests: 4,
            build: .passing,
            tasksTotal: 3,
            tasksPending: 2,
            lastActivity: hoursAgo(2),
            lastCommit: HomeCommitInfo(message: "Feat/Auth", author: accountName, date: hoursAgo(2)),
            commitsLast7Days: [2, 4, 3, 6, 5, 8, 13]
        )
    }

    static var inSync: HomeRepoCardData {
        HomeRepoCardData(
            id: "mock-insync",
            name: "InSync",
            owner: accountName,
            description: "Sincronizador en segundo plano para iOS",
            isFavorite: true,
            status: .stable,
            branch: "main",
            languages: [
                HomeLanguageShare(name: "Swift", share: 0.89),
                HomeLanguageShare(name: "Objective-C", share: 0.11)
            ],
            stars: 1,
            pullRequests: 18,
            alerts: 2,
            lastActivity: hoursAgo(26)
        )
    }

    static var repoMind: HomeRepoCardData {
        HomeRepoCardData(
            id: "mock-repomind",
            name: "RepoMind",
            owner: accountName,
            description: "Gestor de tareas y repositorios GitHub",
            isFavorite: true,
            isOwnApp: true,
            status: .inDevelopment,
            logoAssetName: "AppLogo",
            languages: [HomeLanguageShare(name: "Swift", share: 1)],
            tasksTotal: 3,
            tasksPending: 2,
            taskPreview: [
                HomeTaskPreview(id: UUID(), title: "Rediseñar UI", isDone: false),
                HomeTaskPreview(id: UUID(), title: "Conectar API", isDone: true),
                HomeTaskPreview(id: UUID(), title: "Ajustar base de datos", isDone: false)
            ],
            lastActivity: hoursAgo(5)
        )
    }

    static var rentalManagerIOS: HomeRepoCardData {
        HomeRepoCardData(
            id: "mock-rentalmngr-ios",
            name: "RentalMngr-iOS",
            owner: accountName,
            description: "Gestión de propiedades de alquiler para pequeños propietarios",
            isFavorite: true,
            status: .beta,
            version: "v1.4.0-beta",
            languages: [
                HomeLanguageShare(name: "Swift", share: 0.75),
                HomeLanguageShare(name: "Kotlin", share: 0.25)
            ],
            stars: 12,
            collaborators: 2,
            tasksTotal: 3,
            tasksPending: 3,
            lastActivity: hoursAgo(72)
        )
    }

    static var clarity: HomeRepoCardData {
        HomeRepoCardData(
            id: "mock-clarity",
            name: "Clarity",
            owner: accountName,
            description: "App de iOS para gestionar los gastos",
            isFavorite: true,
            status: .maintenance,
            languages: [
                HomeLanguageShare(name: "HTML", share: 0.6),
                HomeLanguageShare(name: "CSS", share: 0.4)
            ],
            stars: 1,
            pullRequests: 3,
            lastActivity: hoursAgo(24 * 7),
            commitsLast7Days: [1, 0, 2, 1, 0, 3, 1]
        )
    }

    static var rentalManagerWeb: HomeRepoCardData {
        HomeRepoCardData(
            id: "mock-rental-manager",
            name: "rental-manager",
            owner: accountName,
            description: "Panel web para gestionar alquileres",
            isFavorite: true,
            status: .inactive,
            languages: [HomeLanguageShare(name: "Svelte", share: 1)],
            stars: 1,
            pullRequests: 0,
            tasksTotal: 1,
            tasksPending: 1,
            lastActivity: hoursAgo(24 * 60)
        )
    }

    private static func hoursAgo(_ hours: Double) -> Date {
        Date.now.addingTimeInterval(-hours * 3600)
    }
}
