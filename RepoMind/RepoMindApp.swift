import SwiftData
import SwiftUI

#if canImport(UIKit)
    class AppDelegate: NSObject, UIApplicationDelegate {
        func application(
            _ application: UIApplication,
            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
        ) -> Bool {
            application.registerForRemoteNotifications()
            if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
                QuickActionRouter.shared.pendingItem = shortcutItem
            }
            return true
        }

        func application(
            _ application: UIApplication,
            didReceiveRemoteNotification userInfo: [AnyHashable: Any],
            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
        ) {
            completionHandler(.newData)
        }

        func application(
            _ application: UIApplication,
            performActionFor shortcutItem: UIApplicationShortcutItem,
            completionHandler: @escaping (Bool) -> Void
        ) {
            QuickActionRouter.shared.handle(shortcutItem)
            completionHandler(true)
        }
    }
#endif

@main
struct RepoMindApp: App {
    #if canImport(UIKit)
        @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    let container: ModelContainer
    private let initError: String?

    @State private var showQuickAddTask = false

    init() {
        _ = SubscriptionManager.shared

        // Cache de imágenes en disco para logos (50MB memoria, 200MB disco)
        URLCache.shared = URLCache(
            memoryCapacity: 50_000_000,
            diskCapacity: 200_000_000
        )

        let schema = Schema([
            GitHubAccount.self,
            ProjectRepo.self,
            KanbanColumn.self,
            TaskItem.self,
            FeedbackIssue.self,
        ])

        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .automatic
        )

        do {
            container = try ModelContainer(for: schema, configurations: [config])
            initError = nil
        } catch {
            // Fallback to in-memory container so the app doesn't crash
            container = try! ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            ])
            initError = error.localizedDescription
        }

        FeedbackNotificationManager.shared.registerBackgroundTask(container: container)
    }

    var body: some Scene {
        WindowGroup {
            if let initError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text("Database Error")
                        .font(.title2.bold())
                    Text(initError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Text("Try reinstalling the app or contact support.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentView()
                    .onAppear {
                        #if targetEnvironment(macCatalyst)
                            configureMacWindow()
                        #endif
                        FeedbackNotificationManager.shared.scheduleNextRefresh()
                        #if canImport(UIKit)
                            QuickActionRouter.shared.consumePendingIfNeeded()
                        #endif
                    }
                    .task {
                        // Skip when not authenticated or in demo mode (no real repos to sync).
                        let isAuth = UserDefaults.standard.bool(forKey: "isAuthenticated")
                        let isDemo = UserDefaults.standard.bool(forKey: "isDemoMode")
                        guard isAuth, !isDemo else { return }
                        await FeedbackNotificationManager.shared.syncAllInForeground(container: container)
                    }
                    .onOpenURL { url in
                        DeepLinkHandler.handle(url, in: container.mainContext)
                    }
                    .sheet(isPresented: $showQuickAddTask) {
                        QuickAddTaskView()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .quickActionTriggered)) { note in
                        if (note.userInfo?["type"] as? String) == QuickActionRouter.quickAddTaskType {
                            showQuickAddTask = true
                        }
                    }
            }
        }
        .modelContainer(container)
        .commands {
            RepoMindCommands()
        }
    }

#if targetEnvironment(macCatalyst)
        private func configureMacWindow() {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            else { return }
            windowScene.sizeRestrictions?.minimumSize = CGSize(
                width: MacDesign.minWindowWidth,
                height: MacDesign.minWindowHeight
            )
            windowScene.title = "RepoMind"
        }
    #endif
}
