import Foundation
import SwiftData

// MARK: - Deep Link Handler
//
// URL Scheme: repomind://
//
// Supported actions:
//
//   repomind://add-task?content=Fix+login+bug&repo=my-app&column=To-Do
//     - content (required): task text
//     - repo (optional): repo name to target. If omitted, uses the first repo.
//     - column (optional): column name. If omitted, uses the first column.
//
//   repomind://open-repo?name=my-app
//     - name (required): repo name to navigate to
//

@MainActor
enum DeepLinkHandler {

    static func handle(_ url: URL, in context: ModelContext) {
        guard url.scheme == "repomind" else { return }

        switch url.host {
        case "add-task":
            handleAddTask(url: url, context: context)
        default:
            #if DEBUG
            print("[DeepLink] Unknown action: \(url.host ?? "nil")")
            #endif
        }
    }

    // MARK: - Add Task

    private static func handleAddTask(url: URL, context: ModelContext) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems
        else { return }

        let content = queryItems.first { $0.name == "content" }?.value
        let repoName = queryItems.first { $0.name == "repo" }?.value
        let columnName = queryItems.first { $0.name == "column" }?.value

        guard let content, !content.isEmpty else {
            #if DEBUG
            print("[DeepLink] add-task: missing 'content' parameter")
            #endif
            return
        }

        // Find target repo
        let repo: ProjectRepo?
        if let repoName {
            let allRepos = (try? context.fetch(FetchDescriptor<ProjectRepo>())) ?? []
            // Exact match wins. Matching on substring alone sent `repo=api` to "api-legacy",
            // silently filing the task against the wrong project.
            repo = allRepos.first { $0.name.localizedCompare(repoName) == .orderedSame }
                ?? allRepos.first { $0.name.localizedStandardContains(repoName) }
        } else {
            repo = try? context.fetch(
                FetchDescriptor<ProjectRepo>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            ).first
        }

        guard let repo else {
            ToastManager.shared.show(
                String(localized: "deeplink_no_repo_error"),
                style: .error
            )
            return
        }

        // Find target column
        let columns = (repo.columns ?? []).sorted { $0.orderIndex < $1.orderIndex }
        let column: KanbanColumn?
        if let columnName {
            column = columns.first { $0.name.localizedStandardContains(columnName) }
        } else {
            column = columns.first
        }

        guard let column else {
            ToastManager.shared.show(
                String(localized: "deeplink_no_column_error"),
                style: .error
            )
            return
        }

        // Create task
        let maxOrder = (column.tasks ?? []).map(\.orderIndex).max() ?? -1
        let task = TaskItem(
            content: content,
            status: column.name.lowercased().replacingOccurrences(of: " ", with: "_"),
            column: column,
            project: repo,
            orderIndex: maxOrder + 1
        )
        context.insert(task)
        do {
            try context.save()
        } catch {
            // Never claim success for something that was not persisted.
            ToastManager.shared.show(String(localized: "task_save_failed"), style: .error)
            return
        }

        ToastManager.shared.show(
            String(format: String(localized: "deeplink_task_created"), repo.name),
            style: .success
        )

        #if DEBUG
        print("[DeepLink] Task created: '\(content)' in \(repo.name)/\(column.name)")
        #endif
    }
}
