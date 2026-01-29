import SwiftData
import SwiftUI

@main
struct RepoMindApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: ProjectRepo.self, TaskItem.self)
        } catch {
            // Migration failed — delete the old store and create a fresh one
            let storeURL = URL.applicationSupportDirectory.appending(path: "default.store")
            let related = [storeURL, storeURL.appendingPathExtension("wal"), storeURL.appendingPathExtension("shm")]
            for url in related {
                try? FileManager.default.removeItem(at: url)
            }
            do {
                container = try ModelContainer(for: ProjectRepo.self, TaskItem.self)
            } catch {
                fatalError("Failed to create ModelContainer after reset: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
