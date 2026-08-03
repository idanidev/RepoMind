import Foundation
import SwiftData

/// Mirrors Kanban tasks as GitHub Issues when `ProjectRepo.syncTasksToGitHub` is enabled.
/// Local mutations (SwiftData) always succeed first and are never blocked by network calls —
/// on failure, `TaskItem.needsIssueSync` is set so `reconcile` retries later.
@MainActor
final class TaskIssueSyncService {
    static let shared = TaskIssueSyncService()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    private init() {}

    static let taskLabel = "repomind-task"

    enum SyncError: LocalizedError {
        case noOwner
        case noPermission
        case notFound
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .noOwner: return String(localized: "sync_tasks_error_no_owner")
            case .noPermission: return String(localized: "sync_tasks_disabled_no_permission")
            case .notFound: return String(localized: "sync_tasks_error_not_found")
            case .http(let code, _): return String(format: String(localized: "feedback_error_http %lld"), code)
            }
        }
    }

    // MARK: - Column label slugs

    /// "En progreso" → "col:en-progreso"
    static func columnLabel(for column: KanbanColumn) -> String {
        let slug = column.name
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
        return "col:\(slug)"
    }

    // MARK: - Label bootstrap

    /// Creates `repomind-task` + one `col:*` label per column if missing. Best-effort — failures are ignored.
    func ensureLabels(repo: ProjectRepo, columns: [KanbanColumn], token: String) async {
        guard let (owner, name) = repoOwnerAndName(repo) else { return }
        let existing = (try? await fetchLabelNames(owner: owner, name: name, token: token)) ?? []

        var toCreate: [(name: String, color: String)] = []
        if !existing.contains(Self.taskLabel) {
            toCreate.append((Self.taskLabel, "7C3AED"))
        }
        for column in columns {
            let label = Self.columnLabel(for: column)
            if !existing.contains(label) {
                toCreate.append((label, "EDEDED"))
            }
        }
        for label in toCreate {
            try? await createLabel(owner: owner, name: name, labelName: label.name, color: label.color, token: token)
        }
    }

    private func fetchLabelNames(owner: String, name: String, token: String) async throws -> Set<String> {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(name)/labels?per_page=100")!
        var req = URLRequest(url: url)
        applyHeaders(&req, token: token)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SyncError.http((resp as? HTTPURLResponse)?.statusCode ?? 0, "")
        }
        struct GHLabel: Decodable { let name: String }
        let labels = try JSONDecoder().decode([GHLabel].self, from: data)
        return Set(labels.map(\.name))
    }

    private func createLabel(owner: String, name: String, labelName: String, color: String, token: String) async throws {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(name)/labels")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        applyHeaders(&req, token: token)
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": labelName, "color": color])
        _ = try await session.data(for: req) // ignore 422 (already exists race)
    }

    // MARK: - Create

    func createIssue(for task: TaskItem, repo: ProjectRepo, token: String) async throws {
        guard let (owner, name) = repoOwnerAndName(repo) else { throw SyncError.noOwner }
        guard let column = task.column else { return }

        let url = URL(string: "https://api.github.com/repos/\(owner)/\(name)/issues")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        applyHeaders(&req, token: token)
        let body: [String: Any] = [
            "title": issueTitle(for: task),
            "body": issueBody(for: task),
            "labels": [Self.taskLabel, Self.columnLabel(for: column)]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        try throwIfNeeded(resp, data: data)

        struct Created: Decodable { let number: Int }
        let created = try JSONDecoder().decode(Created.self, from: data)
        task.issueNumber = created.number
        task.needsIssueSync = false
    }

    // MARK: - Update column label

    func updateIssueColumn(for task: TaskItem, repo: ProjectRepo, token: String) async throws {
        guard let issueNumber = task.issueNumber else { return try await createIssue(for: task, repo: repo, token: token) }
        guard let (owner, name) = repoOwnerAndName(repo) else { throw SyncError.noOwner }
        guard let column = task.column else { return }

        let url = URL(string: "https://api.github.com/repos/\(owner)/\(name)/issues/\(issueNumber)/labels")!
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        applyHeaders(&req, token: token)
        req.httpBody = try JSONSerialization.data(withJSONObject: ["labels": [Self.taskLabel, Self.columnLabel(for: column)]])

        let (data, resp) = try await session.data(for: req)
        try throwIfNeeded(resp, data: data)
        task.needsIssueSync = false
    }

    // MARK: - Close / Reopen

    func closeIssue(for task: TaskItem, repo: ProjectRepo, reason: String, token: String) async throws {
        guard let issueNumber = task.issueNumber else { return }
        guard let (owner, name) = repoOwnerAndName(repo) else { throw SyncError.noOwner }

        try await patchState(owner: owner, name: name, issueNumber: issueNumber,
                              state: "closed", stateReason: reason, token: token)
        task.needsIssueSync = false
    }

    func reopenIssue(for task: TaskItem, repo: ProjectRepo, token: String) async throws {
        guard let issueNumber = task.issueNumber else { return }
        guard let (owner, name) = repoOwnerAndName(repo) else { throw SyncError.noOwner }

        try await patchState(owner: owner, name: name, issueNumber: issueNumber,
                              state: "open", stateReason: nil, token: token)
        task.needsIssueSync = false
    }

    private func patchState(owner: String, name: String, issueNumber: Int, state: String, stateReason: String?, token: String) async throws {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(name)/issues/\(issueNumber)")!
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        applyHeaders(&req, token: token)
        var body: [String: Any] = ["state": state]
        if let stateReason { body["state_reason"] = stateReason }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        try throwIfNeeded(resp, data: data)
    }

    // MARK: - Delete (close as not_planned + comment)

    func deleteIssue(issueNumber: Int, repo: ProjectRepo, token: String) async throws {
        guard let (owner, name) = repoOwnerAndName(repo) else { throw SyncError.noOwner }
        try await patchState(owner: owner, name: name, issueNumber: issueNumber,
                              state: "closed", stateReason: "not_planned", token: token)

        let url = URL(string: "https://api.github.com/repos/\(owner)/\(name)/issues/\(issueNumber)/comments")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        applyHeaders(&req, token: token)
        req.httpBody = try JSONSerialization.data(withJSONObject: ["body": "Task deleted in RepoMind"])
        _ = try? await session.data(for: req) // best-effort, don't fail the delete over a comment
    }

    // MARK: - Update content

    func updateIssueContent(for task: TaskItem, repo: ProjectRepo, token: String) async throws {
        guard let issueNumber = task.issueNumber else { return try await createIssue(for: task, repo: repo, token: token) }
        guard let (owner, name) = repoOwnerAndName(repo) else { throw SyncError.noOwner }

        let url = URL(string: "https://api.github.com/repos/\(owner)/\(name)/issues/\(issueNumber)")!
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        applyHeaders(&req, token: token)
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "title": issueTitle(for: task),
            "body": issueBody(for: task)
        ])
        let (data, resp) = try await session.data(for: req)
        try throwIfNeeded(resp, data: data)
        task.needsIssueSync = false
    }

    // MARK: - Reconciliation

    /// Retries tasks that failed a prior sync attempt (offline / expired token / etc).
    /// Processes at most 20 per call to stay rate-limit friendly; the rest catch up on the next open.
    func reconcile(repo: ProjectRepo, context: ModelContext, token: String) async {
        guard repo.syncTasksToGitHub, repo.syncTasksDisabledReason == nil else { return }
        let repoID = repo.persistentModelID
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate<TaskItem> { $0.project?.persistentModelID == repoID && $0.needsIssueSync }
        )
        guard let pending = try? context.fetch(descriptor), !pending.isEmpty else { return }

        for task in pending.prefix(20) {
            if Task.isCancelled { break }
            do {
                if task.issueNumber == nil {
                    try await createIssue(for: task, repo: repo, token: token)
                    // A task already finished when sync was switched on would otherwise be
                    // published as an open issue and stay open forever: closing only happens when
                    // a task is *moved* into the done column, and this one never moves.
                    if let done = repo.doneColumn, task.column?.id == done.id {
                        try await closeIssue(for: task, repo: repo, reason: "completed", token: token)
                    }
                } else {
                    try await updateIssueColumn(for: task, repo: repo, token: token)
                }
            } catch SyncError.noPermission, SyncError.notFound {
                repo.syncTasksToGitHub = false
                repo.syncTasksDisabledReason = String(localized: "sync_tasks_disabled_no_permission")
                break
            } catch {
                // Leave needsIssueSync = true so the next reconcile retries — but say so, rather
                // than failing as silently as the CloudKit sync used to.
                #if DEBUG
                    print("[TaskIssueSync] task \(task.id) failed to sync: \(error)")
                #endif
            }
        }
        try? context.save()
    }

    // MARK: - One-shot sync (for call sites without a KanbanViewModel)

    /// Fire-and-forget sync for a freshly created task, usable from places that don't have
    /// a per-repo `KanbanViewModel` at hand (e.g. the Home Screen Quick Action's global sheet).
    /// Resolves the token itself; on failure marks `needsIssueSync` so `reconcile` retries later.
    func syncNewTaskInBackground(_ task: TaskItem, repo: ProjectRepo, context: ModelContext) {
        guard repo.syncTasksToGitHub else { return }
        guard let account = repo.account else { return }
        Task {
            guard let token = try? await KeychainManager.shared.retrieveToken(for: account.tokenKey) else {
                task.needsIssueSync = true
                try? context.save()
                return
            }
            do {
                try await self.createIssue(for: task, repo: repo, token: token)
            } catch SyncError.noPermission, SyncError.notFound {
                repo.syncTasksToGitHub = false
                repo.syncTasksDisabledReason = String(localized: "sync_tasks_disabled_no_permission")
            } catch {
                task.needsIssueSync = true
            }
            try? context.save()
        }
    }

    // MARK: - Helpers

    private func issueTitle(for task: TaskItem) -> String {
        let firstLine = task.content.split(separator: "\n").first.map(String.init) ?? task.content
        return String(firstLine.prefix(250))
    }

    private func issueBody(for task: TaskItem) -> String {
        "\(task.content)\n\n<!-- repomind-task:\(task.id.uuidString) -->"
    }

    private func repoOwnerAndName(_ repo: ProjectRepo) -> (owner: String, name: String)? {
        guard !repo.isLocal, let url = URL(string: repo.htmlURL) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let owner = parts.first, !owner.isEmpty else { return nil }
        return (owner, repo.name)
    }

    private func applyHeaders(_ req: inout URLRequest, token: String) {
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    }

    private func throwIfNeeded(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 403, 410: throw SyncError.noPermission
        case 404: throw SyncError.notFound
        default: throw SyncError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }
}
