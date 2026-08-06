import SwiftData
import SwiftUI

/// Puts tasks that lost their column back on their board.
///
/// A task whose `column` is nil is drawn nowhere: the board renders columns and asks each one for
/// its tasks, so an orphan is not "in the wrong place", it is invisible. The only trace left of it
/// was the "not published" count, which is how eight of them went unnoticed.
///
/// They are not corrupt data and nobody deleted those columns — the columns still exist, and each
/// orphan still records the name of the one it was created in. CloudKit stores a relationship as a
/// reference synced separately from the records themselves, so a partial failure (`CKError` 2, as
/// seen in the sync monitor) can land the task without landing its link. SwiftData requires every
/// relationship to be optional precisely because this cannot be prevented, only repaired.
///
/// `status` is what makes repair possible: it holds a slug of the column name from the moment the
/// task was created. It is redundant while everything works, which is why it is marked deprecated
/// for normal use — but when the relationship is gone it is the only surviving evidence of intent.
enum OrphanTaskRepair {
    /// Reattaches every orphan it can place. Returns how many it fixed.
    @MainActor
    @discardableResult
    static func run(context: ModelContext) -> Int {
        // Filtered in Swift rather than with `#Predicate { $0.column == nil }`: comparing a to-one
        // relationship against nil is unreliable in SwiftData, and a throwing fetch here would
        // return zero repairs indistinguishably from having nothing to repair.
        guard let all = try? context.fetch(FetchDescriptor<TaskItem>()) else { return 0 }
        let orphans = all.filter { $0.column == nil }
        guard !orphans.isEmpty else { return 0 }

        var repaired = 0
        for task in orphans {
            guard let project = task.project else { continue }
            let columns = (project.columns ?? []).sorted { $0.orderIndex < $1.orderIndex }
            // A repo with no columns yet is usually one whose data is still arriving from CloudKit.
            // Guessing there would be worse than waiting for the next launch.
            guard !columns.isEmpty else { continue }

            // Fall back to the first column rather than skipping: a task on the wrong board column
            // is recoverable by hand, an invisible one is not.
            let target = columns.first { slug($0.name) == task.status } ?? columns[0]

            task.column = target
            task.orderIndex = ((target.tasks ?? []).map(\.orderIndex).max() ?? -1) + 1
            repaired += 1
        }

        if repaired > 0 { try? context.save() }
        return repaired
    }

    /// Matches how `status` is written at creation time, e.g. "To-Do" → "to-do".
    private static func slug(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: " ", with: "_")
    }
}
