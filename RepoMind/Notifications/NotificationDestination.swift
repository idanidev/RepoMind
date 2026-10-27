import Foundation

/// A target resolved against the store: the screen to open.
enum NotificationDestination {
    case board(ProjectRepo, BoardFocus?)
    case stats(ProjectRepo)
    case web(URL)
}

extension NotificationTarget {
    /// Looks the ids up. nil when the thing is gone (a report deleted, a repo removed), in which
    /// case the tap just leaves the app open where it was.
    @MainActor
    func destination(repos: [ProjectRepo], feedback: [FeedbackIssue]) -> NotificationDestination? {
        switch self {
        case .feedback(let issueID):
            guard let issue = feedback.first(where: { $0.id == issueID }),
                let repo = repos.first(where: { $0.fullName == issue.repoFullName })
            else { return nil }
            return .board(repo, .feedback(issueID))
        case .tasks(let repoID, let taskIDs):
            guard let repo = repos.first(where: { $0.repoID == repoID }) else { return nil }
            let tasks = repo.tasks ?? []
            let found = taskIDs.compactMap { id in tasks.first { $0.id == id } }
            if found.count == 1, let only = found.first {
                return .board(repo, .task(only.id))
            }
            return .board(repo, found.first?.column.map { .column($0.id) })
        case .board(let repoID):
            return repos.first(where: { $0.repoID == repoID }).map { .board($0, nil) }
        case .stats(let repoID):
            return repos.first(where: { $0.repoID == repoID }).map { .stats($0) }
        case .web(let url):
            return .web(url)
        }
    }
}
