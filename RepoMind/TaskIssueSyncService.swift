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
    /// Matches `FeedbackService`: user reports have their own inbox and must not be
    /// duplicated onto the board as tasks.
    static let feedbackLabel = "user-feedback"

    enum SyncError: LocalizedError {
        case noOwner
        case noColumn
        case noPermission
        case notFound
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .noOwner: return String(localized: "sync_tasks_error_no_owner")
            case .noColumn: return String(localized: "sync_tasks_error_no_column")
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
        // This used to `return`, which the caller read as success: `needsIssueSync` stayed set,
        // nothing was retried, and the task sat under "not published" forever with no explanation.
        guard let column = task.column else { throw SyncError.noColumn }

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
        task.lastSyncError = nil
    }

    // MARK: - Update column label

    func updateIssueColumn(for task: TaskItem, repo: ProjectRepo, token: String) async throws {
        guard let issueNumber = task.issueNumber else { return try await createIssue(for: task, repo: repo, token: token) }
        guard let (owner, name) = repoOwnerAndName(repo) else { throw SyncError.noOwner }
        guard let column = task.column else { throw SyncError.noColumn }

        let url = URL(string: "https://api.github.com/repos/\(owner)/\(name)/issues/\(issueNumber)/labels")!
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        applyHeaders(&req, token: token)
        req.httpBody = try JSONSerialization.data(withJSONObject: ["labels": [Self.taskLabel, Self.columnLabel(for: column)]])

        let (data, resp) = try await session.data(for: req)
        try throwIfNeeded(resp, data: data)
        task.needsIssueSync = false
        task.lastSyncError = nil
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
        task.lastSyncError = nil
    }

    // MARK: - Import (GitHub → app)

    /// Brings issues that were closed on GitHub back into the board.
    ///
    /// Everything else in this file pushes: create, update, close, reopen, delete. `reconcile`
    /// only retries *local* changes that failed. So when a coding agent finished a task through
    /// the MCP bridge and called `complete_task`, the issue closed on GitHub and the app never
    /// found out — nothing here read issue state at all. The task sat in To-Do forever.
    ///
    /// Deliberately one-directional: a closed issue moves its task to the done column, but an open
    /// issue never moves a task *out* of done. Which column it should return to is recorded
    /// nowhere, and guessing would rearrange the user's board behind their back.
    /// What a sync round actually did, and when it did nothing, why.
    ///
    /// "Nothing happened" has several causes here and they need different fixes, so a bare count
    /// made this impossible to debug from the outside: sync switched off looked exactly like
    /// everything already being up to date.
    struct ImportResult: Equatable {
        var completed = 0   // tasks moved into the done column because their issue closed
        var imported = 0    // issues opened outside the app, pulled in as tasks
        var changed: Int { completed + imported }
    }

    enum ImportOutcome: Equatable {
        case changed(ImportResult)
        case syncDisabled
        case upToDate
        case requestFailed(String)

        var result: ImportResult { if case .changed(let r) = self { return r } else { return .init() } }
    }

    /// One sentence for whatever the round did. Two separate things can happen in a single sync
    /// and lumping them into one number hid which — "3 tasks" reads very differently from
    /// "2 completed, 1 imported".
    static func summary(for result: ImportResult) -> String {
        if result.completed > 0 && result.imported > 0 {
            return String(
                format: String(localized: "sync_summary_both %lld %lld"),
                result.completed, result.imported)
        }
        if result.imported > 0 {
            return String(format: String(localized: "sync_summary_imported %lld"), result.imported)
        }
        return String(format: String(localized: "tasks_completed_by_agent %lld"), result.completed)
    }

    /// Reconciles a repo's board against its GitHub issues, in both directions.
    ///
    /// Everything else in this file pushes: create, update, close, reopen, delete. `reconcile`,
    /// despite the name, only retries *local* changes that failed. Nothing read issue state back,
    /// so two things were invisible to the app: a task an agent finished through the MCP bridge
    /// (the issue closed on GitHub and the board never knew), and an issue opened straight on
    /// GitHub, which never became a task at all.
    ///
    /// One request per repo covers both — `state=all` and sort it out locally.
    ///
    /// Moving to done is deliberately one-directional: a reopened issue does not pull its task
    /// back *out* of done, because the column it came from is recorded nowhere and guessing would
    /// rearrange the board behind the user's back.
    @discardableResult
    func syncIssues(repo: ProjectRepo, context: ModelContext, token: String) async -> ImportOutcome {
        guard repo.syncTasksToGitHub, repo.syncTasksDisabledReason == nil else { return .syncDisabled }
        guard let (owner, name) = repoOwnerAndName(repo) else { return .syncDisabled }
        let columns = (repo.columns ?? []).sorted { $0.orderIndex < $1.orderIndex }
        guard let done = repo.doneColumn, let inbox = columns.first else { return .syncDisabled }

        let url = URL(
            string: "https://api.github.com/repos/\(owner)/\(name)/issues"
                + "?state=all&per_page=100&sort=updated&direction=desc")!
        var req = URLRequest(url: url)
        applyHeaders(&req, token: token)

        let data: Data
        do {
            let (payload, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                return .requestFailed(SyncError.http(code, "").localizedDescription)
            }
            data = payload
        } catch {
            return .requestFailed(error.localizedDescription)
        }

        struct GHIssue: Decodable {
            struct Label: Decodable { let name: String }
            struct PullRequest: Decodable {}
            let number: Int
            let title: String
            let state: String
            let labels: [Label]
            let pullRequest: PullRequest?

            enum CodingKeys: String, CodingKey {
                case number, title, state, labels
                case pullRequest = "pull_request"
            }
        }
        guard let issues = try? JSONDecoder().decode([GHIssue].self, from: data) else {
            return .requestFailed(SyncError.http(0, "").localizedDescription)
        }

        var result = ImportResult()
        let tasks = repo.tasks ?? []
        let linked = Dictionary(
            tasks.compactMap { task in task.issueNumber.map { ($0, task) } },
            uniquingKeysWith: { first, _ in first })

        for issue in issues {
            // The issues endpoint returns pull requests too, and they are not tasks.
            if issue.pullRequest != nil { continue }
            let labels = Set(issue.labels.map(\.name))
            // User reports have their own inbox; importing them here would duplicate them.
            if labels.contains(Self.feedbackLabel) { continue }

            if let task = linked[issue.number] {
                if issue.state == "closed", task.column?.id != done.id {
                    task.column = done
                    task.orderIndex = ((done.tasks ?? []).map(\.orderIndex).max() ?? -1) + 1
                    result.completed += 1
                }
            } else if issue.state == "open" {
                // Opened straight on GitHub — by the developer, a teammate or an agent. Without
                // this it never reached the board, which is what "my issues don't show up" meant.
                let target = columns.first { labels.contains(Self.columnLabel(for: $0)) } ?? inbox
                let task = TaskItem(
                    content: issue.title,
                    status: target.name.lowercased().replacingOccurrences(of: " ", with: "_"),
                    column: target,
                    project: repo,
                    orderIndex: ((target.tasks ?? []).map(\.orderIndex).max() ?? -1) + 1
                )
                task.issueNumber = issue.number
                context.insert(task)
                result.imported += 1
            }
        }

        if result.changed > 0 {
            try? context.save()
            // Only the imported ones are worth a banner: tasks moving to done are the result of
            // work the developer already knows about, but an issue opened elsewhere is news.
            if result.imported > 0 {
                let name = repo.name
                let count = result.imported
                Task { await FeedbackNotificationManager.shared.notifyImportedTasks(count, repoName: name) }
            }
            return .changed(result)
        }
        return .upToDate
    }

    /// The same reconciliation across every synced repo, resolving each account's token itself.
    ///
    /// Opening a board was the only thing that pulled anything back, so a task an agent finished —
    /// or an issue opened on GitHub — stayed invisible until you happened to visit that project.
    /// One request per synced repo is cheap enough to run from the repo list, unlike the repo list
    /// refresh itself, which is rate-limited and deliberately runs at most once a week on iPhone.
    @discardableResult
    func syncIssuesEverywhere(repos: [ProjectRepo], context: ModelContext) async -> ImportOutcome {
        let eligible = repos.filter { $0.syncTasksToGitHub && $0.syncTasksDisabledReason == nil }
        // Told apart on purpose: no repo publishes its tasks at all, versus they do and there was
        // simply nothing new. Same empty screen, completely different fix.
        guard !eligible.isEmpty else { return .syncDisabled }

        var total = ImportResult()
        var lastFailure: String?
        var reachedAny = false

        for repo in eligible {
            guard let account = repo.account,
                  let token = try? await KeychainManager.shared.retrieveToken(for: account.tokenKey)
            else { continue }

            switch await syncIssues(repo: repo, context: context, token: token) {
            case .changed(let r):
                total.completed += r.completed
                total.imported += r.imported
                reachedAny = true
            case .upToDate:
                reachedAny = true
            case .requestFailed(let reason):
                lastFailure = reason
            case .syncDisabled:
                break
            }
        }

        if total.changed > 0 { return .changed(total) }
        if let lastFailure { return .requestFailed(lastFailure) }
        return reachedAny ? .upToDate : .syncDisabled
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
            // Same rule as runSync: ideas never reach GitHub, so they must not be retried either.
            if repo.isIdea(task) {
                task.needsIssueSync = false
                task.lastSyncError = nil
                continue
            }
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
                // Leave needsIssueSync = true so the next reconcile retries, and record why on the
                // task itself. This used to be a DEBUG-only print, which meant a stuck task was
                // reported as "not published" with the reason existing nowhere the user could see.
                task.lastSyncError = error.localizedDescription
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
                task.lastSyncError = String(localized: "sync_tasks_error_no_token")
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
                task.lastSyncError = error.localizedDescription
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
