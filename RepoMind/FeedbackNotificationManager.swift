import BackgroundTasks
import Foundation
import SwiftData
import UserNotifications

#if canImport(UIKit)
    import UIKit
#endif

@MainActor
final class FeedbackNotificationManager {
    static let shared = FeedbackNotificationManager()

    static let backgroundTaskID = "com.idanidev.repomind.feedback.refresh"
    private let pollInterval: TimeInterval = 15 * 60 // 15 minutes

    private init() {}

    // MARK: - Permission

    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    // MARK: - Notify

    func notify(for new: [FeedbackIssue]) async {
        guard !new.isEmpty else { return }
        let granted = await requestAuthorizationIfNeeded()
        guard granted else { return }

        let center = UNUserNotificationCenter.current()
        for issue in new {
            let content = UNMutableNotificationContent()
            // The app first, what kind of report second, the report itself last: the order a
            // developer reads a lock screen in. Grouped by app, so a burst stacks instead of scrolling.
            content.title = NotificationText.shortRepoName(issue.repoFullName)
            content.subtitle = kind(for: issue.severityEnum)
            content.body = NotificationText.issueLine(number: issue.issueNumber, title: issue.title)
            content.sound = .default
            content.threadIdentifier = "feedback-\(issue.repoFullName)"
            content.relevanceScore = relevance(for: issue.severityEnum)
            content.userInfo = NotificationTarget.feedback(issueID: issue.id).userInfo
            let request = UNNotificationRequest(
                identifier: "feedback-\(issue.id.uuidString)",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    /// Announces issues that arrived from GitHub rather than from this app.
    ///
    /// The board imports them silently, so tasks a teammate — or a coding agent — opened simply
    /// appeared one day with nothing to say they had. One grouped notification per repo, not one
    /// per issue: a sweep can pull in several at once and a burst of banners is worse than none.
    /// It names the first issue, and a tap lands on that task when it was one, on its column otherwise.
    func notifyImportedTasks(_ issues: [TaskIssueSyncService.ImportedIssue], repoID: Int, repoName: String) async {
        guard let first = issues.first, await requestAuthorizationIfNeeded() else { return }

        let line = NotificationText.issueLine(number: first.number, title: first.title)
        let content = UNMutableNotificationContent()
        content.title = repoName
        content.body = issues.count == 1
            ? String(format: String(localized: "notif_imported_one %@"), line)
            : String(format: String(localized: "notif_imported_other %lld %@"), issues.count, line)
        content.sound = .default
        content.threadIdentifier = "imported-\(repoName)"
        content.userInfo = NotificationTarget.tasks(repoID: repoID, taskIDs: issues.map(\.taskID)).userInfo

        let request = UNNotificationRequest(
            identifier: "imported-\(repoName)-\(Date.now.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func kind(for severity: FeedbackSeverity) -> String {
        switch severity {
        case .critical: String(localized: "feedback_notif_kind_critical")
        case .minor: String(localized: "feedback_notif_kind_minor")
        case .enhancement: String(localized: "feedback_notif_kind_enhancement")
        case .general: String(localized: "feedback_notif_kind_general")
        }
    }

    /// How high a report sits in the notification summary the system builds.
    private func relevance(for severity: FeedbackSeverity) -> Double {
        switch severity {
        case .critical: 1.0
        case .minor: 0.6
        case .enhancement: 0.4
        case .general: 0.3
        }
    }

    // MARK: - Foreground Sync

    /// Triggered on app launch / foreground. The alerts, then the feedback poll of every non-local repo.
    func syncAllInForeground(container: ModelContainer) async {
        if SubscriptionManager.shared.isPro, !RepoAlertCenter.shared.enabledKinds.isEmpty {
            // Asked here, while the app is open and a prompt can show: the first alert would otherwise
            // be the first time anyone asks, from a background refresh where no prompt appears.
            _ = await requestAuthorizationIfNeeded()
        }
        await runFullPass(container: container)
    }

    /// The alerts first — what the user is waiting for, and a few requests — then the feedback poll,
    /// which costs one request per repo and, offline, up to thirty seconds each. Checks for
    /// cancellation between steps: a background refresh that overruns its time is cancelled, and what
    /// is half done is simply done again at the next one.
    private func runFullPass(container: ModelContainer) async {
        let context = container.mainContext
        let descriptor = FetchDescriptor<ProjectRepo>(
            predicate: #Predicate { !$0.isLocal && !$0.isArchived }
        )
        guard let checked = try? context.fetch(descriptor), !checked.isEmpty else { return }

        await RepoAlertCenter.shared.check(repos: checked)
        if Task.isCancelled { return }

        // Fetched again: the alerts' requests take a while, and a sign-out or CloudKit removing a duplicate
        // in the meantime deletes models of the first fetch, which must not be read afterwards.
        guard let repos = try? context.fetch(descriptor), !repos.isEmpty else { return }

        // Group by account, only process repos with a token in keychain.
        let accountGroups = Dictionary(grouping: repos) { $0.account?.id }
        var allNew: [FeedbackIssue] = []
        for (_, group) in accountGroups {
            if Task.isCancelled { break }
            guard let account = group.first?.account else { continue }
            let token: String? = try? await KeychainManager.shared.retrieveToken(for: account.tokenKey)
            guard let token else { continue }
            let new = await FeedbackService.shared.syncAll(repos: group, token: token, into: context)
            allNew.append(contentsOf: new)
        }
        await notify(for: allNew)
    }

    // MARK: - Background Refresh

    /// Call from `init()` of the App. Registers the BG handler.
    nonisolated func registerBackgroundTask(container: ModelContainer) {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: Self.backgroundTaskID,
                using: nil
            ) { [container] task in
                guard let refreshTask = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
                Task { @MainActor in
                    await Self.shared.handleBackgroundRefresh(task: refreshTask, container: container)
                }
            }
        #endif
    }

    func scheduleNextRefresh() {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
            let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskID)
            request.earliestBeginDate = Date(timeIntervalSinceNow: pollInterval)
            try? BGTaskScheduler.shared.submit(request)
        #endif
    }

    #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        /// The system gives a refresh about thirty seconds. Work that outlives them is cut off without
        /// anyone telling the scheduler, which then throttles the refreshes that follow: so the pass runs
        /// as a task the expiration handler can cancel, and the task is always reported as completed.
        private func handleBackgroundRefresh(task: BGAppRefreshTask, container: ModelContainer) async {
            scheduleNextRefresh()

            let work = Task { @MainActor in
                await self.runFullPass(container: container)
            }
            // The system calls this from its own queue: not a closure that belongs to the main actor.
            task.expirationHandler = { @Sendable in work.cancel() }
            await work.value
            task.setTaskCompleted(success: !work.isCancelled)
        }
    #endif
}
