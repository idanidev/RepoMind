import Foundation

// MARK: - Mock data

/// Six repos for previews and for trying the screen without an account. Together they exercise
/// every optional row: a featured card with tasks, a private repo with feedback, a failing build,
/// a release tag, a folder and an inactive repo.
///
/// Repo names and descriptions are data the way GitHub would supply them, so they are
/// deliberately not localized.
enum HomeMockData {
    static let accountName = "idanidev"

    static var stats: HomeStats { HomeStats(cards: repos) }

    static var repos: [HomeRepoCardData] {
        [focvs, inSync, repoMind, rentalManagerIOS, clarity, rentalManagerWeb]
    }

    static let webFolder = HomeFolderInfo(id: "mock-folder-web", name: "Web", colorHex: "#5B6CFF", orderIndex: 0)

    static var focvs: HomeRepoCardData {
        HomeRepoCardData(
            id: "mock-focvs",
            name: "FOCVS",
            owner: accountName,
            description: "Temporizador de enfoque con sesiones suaves y un widget discreto",
            isFavorite: true,
            isFeatured: true,
            language: "Swift",
            stars: 12,
            pullRequests: 1,
            version: "v1.2.0",
            tasksTotal: 3,
            tasksPending: 2,
            taskPreview: [
                HomeTaskPreview(id: UUID(), title: "Pantalla de sesión salta con el teclado"),
                HomeTaskPreview(id: UUID(), title: "Widget de bloqueo")
            ],
            lastPush: hoursAgo(2),
            lastActivity: hoursAgo(2)
        )
    }

    static var inSync: HomeRepoCardData {
        HomeRepoCardData(
            id: "mock-insync",
            name: "InSync",
            owner: accountName,
            description: "Sincronizador en segundo plano para iOS",
            isFavorite: true,
            isPrivate: true,
            language: "Swift",
            stars: 1,
            pullRequests: 0,
            alerts: 2,
            lastPush: hoursAgo(26),
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
            logoAssetName: "AppLogo",
            language: "Swift",
            pullRequests: 0,
            unpublished: 1,
            tasksTotal: 3,
            tasksPending: 2,
            lastPush: hoursAgo(5),
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
            language: "Swift",
            stars: 12,
            pullRequests: 0,
            isBuildFailing: true,
            version: "v1.4.0-beta",
            tasksTotal: 3,
            tasksPending: 3,
            lastPush: hoursAgo(72),
            lastActivity: hoursAgo(72)
        )
    }

    static var clarity: HomeRepoCardData {
        HomeRepoCardData(
            id: "mock-clarity",
            name: "Clarity",
            owner: accountName,
            description: "App de iOS para gestionar los gastos",
            folder: webFolder,
            language: "HTML",
            stars: 1,
            pullRequests: 3,
            lastPush: hoursAgo(24 * 7),
            lastActivity: hoursAgo(24 * 7)
        )
    }

    static var rentalManagerWeb: HomeRepoCardData {
        HomeRepoCardData(
            id: "mock-rental-manager",
            name: "rental-manager",
            owner: accountName,
            description: "Panel web para gestionar alquileres",
            isInactive: true,
            folder: webFolder,
            language: "Svelte",
            stars: 1,
            pullRequests: 0,
            tasksTotal: 1,
            tasksPending: 1,
            lastPush: hoursAgo(24 * 200),
            lastActivity: hoursAgo(24 * 200)
        )
    }

    private static func hoursAgo(_ hours: Double) -> Date {
        Date.now.addingTimeInterval(-hours * 3600)
    }
}
