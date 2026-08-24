import SwiftData
import SwiftUI

/// Collapses duplicate accounts and repositories back into one record each.
///
/// CloudKit forbids `@Attribute(.unique)`, so nothing in the store stops the same account or the
/// same repository existing twice — uniqueness has to be enforced by hand, and until now it was
/// only enforced *within* one account:
///
/// ```swift
/// let ownedLocal = allLocal.filter { $0.account?.id == account.id || $0.account == nil }
/// ```
///
/// With two `GitHubAccount` rows for the same username, the pass for the first never sees the
/// repositories hanging off the second. It reads them as new and inserts its own copies, so every
/// sync can duplicate the whole catalogue again.
///
/// Repairing is safe in a way merging usually is not: duplicates of a GitHub repository are copies
/// of the same remote thing, so the only real content is whatever tasks were filed against each.
/// Keeping the copy with the most tasks and moving the rest across loses nothing.
enum DuplicateRepair {
    struct Result: Equatable {
        var accountsMerged = 0
        var reposMerged = 0
        var changed: Bool { accountsMerged > 0 || reposMerged > 0 }
    }

    @MainActor
    @discardableResult
    static func run(context: ModelContext) -> Result {
        var result = Result()
        result.accountsMerged = mergeAccounts(context: context)
        result.reposMerged = mergeRepos(context: context)
        if result.changed { try? context.save() }
        return result
    }

    /// One record per username. The survivor is the one with the most repositories, so the merge
    /// moves as little as possible.
    @MainActor
    private static func mergeAccounts(context: ModelContext) -> Int {
        guard let accounts = try? context.fetch(FetchDescriptor<GitHubAccount>()) else { return 0 }
        let groups = Dictionary(grouping: accounts) { $0.username.lowercased() }

        var merged = 0
        for (_, group) in groups where group.count > 1 {
            let ordered = group.sorted { ($0.repos?.count ?? 0) > ($1.repos?.count ?? 0) }
            guard let survivor = ordered.first else { continue }

            for duplicate in ordered.dropFirst() {
                for repo in duplicate.repos ?? [] {
                    repo.account = survivor
                }
                context.delete(duplicate)
                merged += 1
            }
        }
        return merged
    }

    /// One record per GitHub repository id.
    ///
    /// Local projects are left alone on purpose: they carry no GitHub id, so they all share
    /// `repoID == 0`, and treating that as a duplicate key would merge unrelated projects that
    /// happen to have been created by hand.
    @MainActor
    private static func mergeRepos(context: ModelContext) -> Int {
        guard let repos = try? context.fetch(FetchDescriptor<ProjectRepo>()) else { return 0 }
        let groups = Dictionary(grouping: repos.filter { $0.repoID != 0 && !$0.isLocal }, by: \.repoID)

        var merged = 0
        for (_, group) in groups where group.count > 1 {
            let ordered = group.sorted { ($0.tasks?.count ?? 0) > ($1.tasks?.count ?? 0) }
            guard let survivor = ordered.first else { continue }

            let survivorColumns = (survivor.columns ?? []).sorted { $0.orderIndex < $1.orderIndex }

            for duplicate in ordered.dropFirst() {
                // Tasks move across; a task is real work and must never be lost to a merge.
                //
                // Reassigning `project` alone is not enough, and getting this wrong destroys data:
                // `ProjectRepo.columns` cascades, so deleting the duplicate deletes its columns,
                // and `KanbanColumn.tasks` cascades in turn — every task still pointing at one of
                // those columns would be deleted with it. Each task is repointed at the equivalent
                // column on the survivor first, matched by name, falling back to the first column.
                for task in duplicate.tasks ?? [] {
                    let name = task.column?.name
                    task.column = survivorColumns.first { $0.name == name } ?? survivorColumns.first
                    task.project = survivor
                }
                if survivor.folder == nil, let folder = duplicate.folder {
                    survivor.folder = folder
                }
                // Keep whichever copy actually has an icon. New repos are inserted with
                // `logoURL: nil`, so a duplicate is usually the blank one — but not always, and
                // dropping a user-chosen icon during a merge would look exactly like the bug this
                // repair exists to fix.
                if survivor.logoURL == nil, let logo = duplicate.logoURL {
                    survivor.logoURL = logo
                }
                survivor.isFavorite = survivor.isFavorite || duplicate.isFavorite
                context.delete(duplicate)
                merged += 1
            }
        }
        return merged
    }
}
