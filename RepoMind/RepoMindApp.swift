import CloudKit
import CoreData
import SwiftData
import SwiftUI

#if canImport(UIKit)
    class AppDelegate: NSObject, UIApplicationDelegate {
        func application(
            _ application: UIApplication,
            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? =
                nil
        ) -> Bool {
            // Essential for CloudKit to dispatch silent push notifications immediately
            application.registerForRemoteNotifications()
            return true
        }

        func application(
            _ application: UIApplication,
            didReceiveRemoteNotification userInfo: [AnyHashable: Any],
            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
        ) {
            #if DEBUG
            print("☁️ [AppDelegate] didReceiveRemoteNotification: \(userInfo)")
            #endif
            completionHandler(.newData)
        }
    }
#endif

@main
struct RepoMindApp: App {
    #if canImport(UIKit)
        @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    let container: ModelContainer

    init() {
        // Initialize subscription manager early so transaction listener starts
        _ = SubscriptionManager.shared

        // Schema con todos los modelos
        let schema = Schema([
            GitHubAccount.self,
            ProjectRepo.self,
            KanbanColumn.self,
            TaskItem.self,
        ])

        // Configuración con CloudKit sync automático
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            cloudKitDatabase: .automatic
        )

        do {
            container = try ModelContainer(for: schema, configurations: [config])
            #if DEBUG
            print("☁️ [CloudKit] ModelContainer creado con cloudKitDatabase: .automatic")
            #endif
        } catch {
            #if DEBUG
            print("⚠️ Migration error: \(error)")
            #endif

            // NO borramos datos - solo logueamos el error
            // El usuario debe decidir qué hacer
            fatalError(
                """
                Migration failed. Your data is safe but the app cannot start.
                Error: \(error)

                Please contact support or reinstall the app.
                """)
        }

        // Verificar estado de iCloud (solo en debug)
        #if DEBUG
            checkCloudKitStatus()
        #endif
    }

    private func checkCloudKitStatus() {
        CKContainer(identifier: "iCloud.idanidev.RepoMind").accountStatus { status, error in
            switch status {
            case .available:
                print("☁️ [CloudKit] iCloud account DISPONIBLE - sync debería funcionar")
            case .noAccount:
                print("❌ [CloudKit] NO hay cuenta iCloud en este dispositivo")
            case .restricted:
                print("❌ [CloudKit] Cuenta iCloud RESTRINGIDA")
            case .couldNotDetermine:
                print(
                    "❌ [CloudKit] No se pudo determinar estado: \(error?.localizedDescription ?? "unknown")"
                )
            case .temporarilyUnavailable:
                print("⚠️ [CloudKit] iCloud temporalmente no disponible")
            @unknown default:
                print("❓ [CloudKit] Estado desconocido: \(status.rawValue)")
            }
        }

        // Verificar que el container existe y es accesible
        let container = CKContainer(identifier: "iCloud.idanidev.RepoMind")
        print("☁️ [CloudKit] Container ID: \(container.containerIdentifier ?? "nil")")

        container.fetchUserRecordID { recordID, error in
            if let recordID {
                print("☁️ [CloudKit] User Record ID: \(recordID.recordName) - conexión OK")
            } else {
                print(
                    "❌ [CloudKit] Error obteniendo user record: \(error?.localizedDescription ?? "unknown")"
                )
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    #if targetEnvironment(macCatalyst)
                        configureMacWindow()
                    #endif
                    #if DEBUG
                        diagnoseCloudKitSync()
                    #endif
                }
        }
        .modelContainer(container)
        .commands {
            RepoMindCommands()
        }
    }

    // Static flag — App is a struct so instance vars can't be mutated
    private static var hasRegisteredSyncObservers = false

    @MainActor
    private func diagnoseCloudKitSync() {
        let context = container.mainContext
        do {
            let accounts = try context.fetch(FetchDescriptor<GitHubAccount>())
            let repos = try context.fetch(FetchDescriptor<ProjectRepo>())
            let tasks = try context.fetch(FetchDescriptor<TaskItem>())
            let columns = try context.fetch(FetchDescriptor<KanbanColumn>())
            print(
                "☁️ [CloudKit] Datos locales: \(accounts.count) accounts, \(repos.count) repos, \(columns.count) columns, \(tasks.count) tasks"
            )
        } catch {
            print("❌ [CloudKit] Error fetch: \(error)")
        }

        // Registrar observers solo una vez
        guard !Self.hasRegisteredSyncObservers else { return }
        Self.hasRegisteredSyncObservers = true

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NSPersistentStoreRemoteChangeNotification"),
            object: nil,
            queue: .main
        ) { _ in
            print("☁️ [CloudKit] REMOTE CHANGE recibido")
        }

        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreCoordinatorStoresDidChange,
            object: nil,
            queue: .main
        ) { notification in
            print("☁️ [CloudKit] Store DID CHANGE: \(notification.userInfo ?? [:])")
        }

        print("☁️ [CloudKit] Listeners de sync registrados")
    }

    #if targetEnvironment(macCatalyst)
        private func configureMacWindow() {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            else { return }
            windowScene.sizeRestrictions?.minimumSize = CGSize(width: 900, height: 600)
            windowScene.title = "RepoMind"
        }
    #endif
}
