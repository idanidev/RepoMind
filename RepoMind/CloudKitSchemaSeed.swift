#if DEBUG
import SwiftData
import SwiftUI

/// Forces CloudKit to materialise the schema for newly added model types.
///
/// CloudKit only generates schema in the Development environment, and only when a record of that
/// type is actually written. A type nobody has saved yet simply does not exist there, so it cannot
/// be deployed to Production — and in Production, writing an unknown type fails outright rather
/// than creating it. That is how `RepoFolder` ended up missing from both environments while the
/// app quietly failed every folder sync.
///
/// Relying on someone tapping through the UI to trigger that write is fragile, so this does it on
/// demand: launch with `-seedCloudKitSchema` once, against a build signed for Development, and
/// every new type and field gets created. DEBUG-only; it never ships.
enum CloudKitSchemaSeed {
    private static let seedName = "schema-seed"

    /// Removes the records `runIfRequested` inserted.
    ///
    /// Seeding writes real rows into the real database, and they show up in the UI like anything
    /// else. Calling them harmless was wrong: leaving debris in someone's live data is not a
    /// detail. Matches the exact seed name only, and reports anything from an older seeding run
    /// rather than guessing at it.
    static func cleanIfRequested(container: ModelContainer) {
        guard CommandLine.arguments.contains("-cleanSchemaSeed") else { return }

        let context = ModelContext(container)
        var removed = 0

        if let folders = try? context.fetch(FetchDescriptor<RepoFolder>()) {
            for folder in folders where folder.name == seedName {
                context.delete(folder)
                removed += 1
            }
        }
        if let tasks = try? context.fetch(FetchDescriptor<TaskItem>()) {
            for task in tasks where task.content == seedName {
                context.delete(task)
                removed += 1
            }
        }

        // Anything left from the July SCHEMA_INIT run is not ours to delete unprompted.
        if let repos = try? context.fetch(FetchDescriptor<ProjectRepo>()) {
            for repo in repos where repo.name.lowercased().contains("schema") {
                print("🌱 [SchemaSeed] Older leftover, NOT deleted: ProjectRepo \(repo.name) favourite=\(repo.isFavorite)")
            }
        }

        try? context.save()
        print("🌱 [SchemaSeed] Removed \(removed) seed records.")
    }

    static func runIfRequested(container: ModelContainer) {
        guard CommandLine.arguments.contains("-seedCloudKitSchema") else { return }

        let context = ModelContext(container)
        let folder = RepoFolder(name: seedName, colorHex: "#5B6CFF", orderIndex: 999)
        context.insert(folder)

        // A task carrying every newer field, so the columns exist too.
        let task = TaskItem(content: seedName)
        task.lastSyncError = seedName
        task.needsIssueSync = false
        task.issueNumber = 0
        context.insert(task)

        do {
            try context.save()
            print("🌱 [SchemaSeed] Inserted RepoFolder + TaskItem. Give CloudKit a few seconds to export.")
        } catch {
            print("🌱 [SchemaSeed] FAILED: \(error)")
        }
    }
}
#endif
