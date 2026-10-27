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

    static var digest: HomeDigest {
        HomeDigest(
            abandoned: 4, unpublished: 2, syncErrors: 1, failingBuilds: 1, pullRequests: 3,
            unreadFeedback: 2, dormantRepos: 1, capturedThisWeek: 7,
            apps: [
                HomeDigestApp(
                    repoID: -2, name: "InSync", headline: "31 Activas 7 días", change: 0.12,
                    crashes: 2, reports: 1)
            ])
    }

    static var repos: [HomeRepoCardData] {
        [focvs, inSync, repoMind, rentalManagerIOS, clarity, rentalManagerWeb]
    }

    static var taskRows: [HomeTaskRow] {
        [
            HomeTaskRow(
                id: UUID(), title: "Android: un solo canal de realtime por grupo", repoName: "InSync",
                repoCardID: "mock-insync", columnName: "To Do", createdAt: hoursAgo(1), issueNumber: 142,
                needsIssueSync: false, state: .pending),
            HomeTaskRow(
                id: UUID(), title: "Revisar política de privacidad", repoName: "InSync",
                repoCardID: "mock-insync", columnName: "To Do", createdAt: hoursAgo(30), issueNumber: nil,
                needsIssueSync: true, state: .pending),
            HomeTaskRow(
                id: UUID(), title: "Pantalla de sesión salta con el teclado", repoName: "FOCVS",
                repoCardID: "mock-focvs", columnName: "Done", createdAt: hoursAgo(5), issueNumber: 12,
                needsIssueSync: false, state: .done),
            HomeTaskRow(
                id: UUID(), title: "Modo widget en el reloj", repoName: "FOCVS",
                repoCardID: "mock-focvs", columnName: "Ideas", createdAt: hoursAgo(80), issueNumber: nil,
                needsIssueSync: false, state: .idea)
        ]
    }

    static var dashboard: HomeDashboardData {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let perDay = [2, 0, 1, 3, 0, 0, 4, 1, 2, 0, 1, 5, 2, 3]
        let history = (0..<HomeDashboardData.historyDays).reversed().map { offset in
            HomeDayCount(
                date: calendar.date(byAdding: .day, value: -offset, to: today) ?? today,
                count: perDay[offset % perDay.count])
        }
        return HomeDashboardData(
            accountNames: [accountName],
            isPro: true,
            digest: digest,
            tasks: HomeTaskTotals(total: 214, pending: 46, done: 150, ideas: 18, capturedToday: 3, capturedWeek: 11),
            captureHistory: history,
            recent: [
                HomeRecentTask(
                    id: UUID(), title: "Android: un solo canal de realtime por grupo", repoName: "InSync",
                    repoCardID: "mock-insync", createdAt: hoursAgo(1), isDone: false),
                HomeRecentTask(
                    id: UUID(), title: "Pantalla de sesión salta con el teclado", repoName: "FOCVS",
                    repoCardID: "mock-focvs", createdAt: hoursAgo(5), isDone: true),
                HomeRecentTask(
                    id: UUID(), title: "Exportar gastos a CSV", repoName: "Clarity",
                    repoCardID: "mock-clarity", createdAt: hoursAgo(28), isDone: false)
            ],
            busiest: [
                HomeRepoLoad(id: "mock-insync", name: "InSync", pending: 18, total: 96),
                HomeRepoLoad(id: "mock-rental-ios", name: "RentalMngr-iOS", pending: 9, total: 33),
                HomeRepoLoad(id: "mock-clarity", name: "Clarity", pending: 3, total: 68)
            ],
            github: HomeGitHubSummary(
                known: 6, pushedToday: 2, pushedWeek: 4, openPullRequests: 3, failing: ["RentalMngr-Web"],
                privateRepos: 2, publicRepos: 4,
                recentPushes: [
                    HomeRepoPush(id: "mock-focvs", name: "FOCVS", pushedAt: hoursAgo(2)),
                    HomeRepoPush(id: "mock-clarity", name: "Clarity", pushedAt: hoursAgo(3)),
                    HomeRepoPush(id: "mock-insync", name: "InSync", pushedAt: hoursAgo(26))
                ],
                releases: [HomeRepoRelease(id: "mock-focvs", name: "FOCVS", tag: "v1.2.0")]),
            apps: [
                HomeAppSummary(
                    app: HomeDigestApp(
                        repoID: -2, name: "InSync", headline: "31 Activas 7 días", change: 0.12,
                        crashes: 2, reports: 1),
                    headlines: [
                        HomeHeadlineValue(id: "accounts", label: "Cuentas", value: 128),
                        HomeHeadlineValue(id: "couples", label: "Parejas", value: 41),
                        HomeHeadlineValue(id: "paying", label: "De pago", value: 9)
                    ],
                    sparkline: [3, 5, 4, 6, 8, 7, 9, 6, 10, 12, 9, 11, 13, 12],
                    periodDays: 30)
            ],
            languages: [
                HomeLanguageShare(id: "Swift", count: 4),
                HomeLanguageShare(id: "HTML", count: 1),
                HomeLanguageShare(id: "TypeScript", count: 1)
            ],
            sync: HomeSyncStatus(
                iCloudProblem: nil, iCloudLastSuccess: hoursAgo(0.2), lastGitHubSync: hoursAgo(1),
                activityRefreshedAt: hoursAgo(0.5)),
            repos: HomeRepoCounts(total: 6, favorites: 3, archived: 1, local: 0, folders: 1, accounts: 1)
        )
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
            highlight: "31 Activas 7 días",
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
