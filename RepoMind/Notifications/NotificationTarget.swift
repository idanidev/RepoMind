import Foundation

// MARK: - Board focus

/// Where a board should land when it is opened from a notification rather than from the list.
nonisolated enum BoardFocus: Hashable, Sendable {
    /// The task, open on its edit sheet.
    case task(UUID)
    /// The column that holds what the notification was about, when it was several tasks.
    case column(UUID)
    /// A report from the users of the app, open on its detail.
    case feedback(UUID)
}

// MARK: - Target

/// Where a notification leads. It travels in the notification's `userInfo`, so it is plain
/// values: ids and a URL, never models. A tap can cold-launch the app long before any model
/// exists, and the id is what the screen looks up once the store is there.
nonisolated enum NotificationTarget: Hashable, Sendable {
    /// A report from the users of an app, on its detail.
    case feedback(issueID: UUID)
    /// Tasks that came in from GitHub: the board, on the task when it was one, on its column otherwise.
    case tasks(repoID: Int, taskIDs: [UUID])
    /// A repo's board.
    case board(repoID: Int)
    /// The statistics of an app.
    case stats(repoID: Int)
    /// A page on GitHub, where the answer to a red build or a security alert lives.
    case web(URL)

    private enum Key {
        static let target = "target"
        static let repoID = "repoID"
        static let issueID = "issueID"
        static let taskIDs = "taskIDs"
        static let url = "url"
        /// What the first version of the feedback notification carried, still sitting in the
        /// notification center of anyone who has not cleared it.
        static let legacyFeedbackIssue = "feedbackIssueID"
    }

    var userInfo: [String: Any] {
        switch self {
        case .feedback(let issueID):
            return [Key.target: "feedback", Key.issueID: issueID.uuidString]
        case .tasks(let repoID, let taskIDs):
            return [Key.target: "tasks", Key.repoID: repoID, Key.taskIDs: taskIDs.map(\.uuidString)]
        case .board(let repoID):
            return [Key.target: "board", Key.repoID: repoID]
        case .stats(let repoID):
            return [Key.target: "stats", Key.repoID: repoID]
        case .web(let url):
            return [Key.target: "web", Key.url: url.absoluteString]
        }
    }

    static func parse(_ userInfo: [AnyHashable: Any]) -> NotificationTarget? {
        if let kind = userInfo[Key.target] as? String {
            switch kind {
            case "feedback":
                return uuid(userInfo[Key.issueID]).map { .feedback(issueID: $0) }
            case "tasks":
                guard let repoID = userInfo[Key.repoID] as? Int else { return nil }
                let raw = userInfo[Key.taskIDs] as? [String] ?? []
                return .tasks(repoID: repoID, taskIDs: raw.compactMap(UUID.init(uuidString:)))
            case "board":
                return (userInfo[Key.repoID] as? Int).map { .board(repoID: $0) }
            case "stats":
                return (userInfo[Key.repoID] as? Int).map { .stats(repoID: $0) }
            case "web":
                return SafeLink.web(userInfo[Key.url] as? String).map { .web($0) }
            default:
                return nil
            }
        }
        return uuid(userInfo[Key.legacyFeedbackIssue]).map { .feedback(issueID: $0) }
    }

    private static func uuid(_ value: Any?) -> UUID? {
        (value as? String).flatMap(UUID.init(uuidString:))
    }
}

// MARK: - Text

/// The words of a notification, in plain functions so they can be tested and so every
/// notification of the app is written the same way.
nonisolated enum NotificationText {
    /// "#12 The shifts screen crashes": the number first, because that is how a developer says it,
    /// on one line and not longer than a banner can show.
    static func issueLine(number: Int, title: String, limit: Int = 120) -> String {
        let flat = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let clipped = flat.count > limit ? String(flat.prefix(limit - 1)) + "…" : flat
        return number > 0 ? "#\(number) \(clipped)" : clipped
    }

    /// The last path component of `owner/name`.
    static func shortRepoName(_ fullName: String) -> String {
        fullName.split(separator: "/").last.map(String.init) ?? fullName
    }
}
