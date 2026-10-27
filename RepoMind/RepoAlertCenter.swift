import Foundation
import SwiftData
import UserNotifications

// MARK: - Rules

/// What deserves a notification, decided from what GitHub and the app backends said this time
/// against what they said last time. Pure, so the rules are testable without a device.
nonisolated enum RepoAlertRules {
    enum Kind: String, CaseIterable, Identifiable, Codable {
        case ci
        case releases
        case security
        case crashes

        var id: String { rawValue }
        var defaultsKey: String { "alerts_" + rawValue }
    }

    /// What was seen last time for one repo. Nil fields mean "never seen", and the first sight
    /// of anything is recorded, never announced: a fresh install is not twelve pieces of news.
    struct Seen: Codable, Hashable {
        var checksState: String?
        var releaseTag: String?
        var securityAlerts: Int?
        /// The newest crash's date and the crash count the stats carried, as text.
        var crashSignature: String?
    }

    struct Alert: Hashable {
        let kind: Kind
        let repoID: Int
        let title: String
        let body: String
    }

    static func gitHubAlerts(
        previous: Seen?, activity: RepoActivity, repoName: String, enabled: Set<Kind>
    ) -> (alerts: [Alert], seen: Seen) {
        var alerts: [Alert] = []
        var seen = previous ?? Seen()

        if let state = activity.checksState {
            let wasKnownAndFine = seen.checksState.map { $0 != "FAILURE" && $0 != "ERROR" } ?? false
            if enabled.contains(.ci), wasKnownAndFine, activity.isBuildFailing {
                alerts.append(Alert(
                    kind: .ci, repoID: activity.repoID,
                    title: String(format: String(localized: "alert_ci_title %@"), repoName),
                    body: String(localized: "alert_ci_body")))
            }
            seen.checksState = state
        }

        if let tag = activity.latestReleaseTag {
            if enabled.contains(.releases), let known = seen.releaseTag, known != tag {
                alerts.append(Alert(
                    kind: .releases, repoID: activity.repoID,
                    title: String(format: String(localized: "alert_release_title %@"), repoName),
                    body: String(format: String(localized: "alert_release_body %@"), tag)))
            }
            seen.releaseTag = tag
        }

        if let count = activity.securityAlerts {
            if enabled.contains(.security), let known = seen.securityAlerts, count > known {
                alerts.append(Alert(
                    kind: .security, repoID: activity.repoID,
                    title: String(format: String(localized: "alert_security_title %@"), repoName),
                    body: String(format: String(localized: "alert_security_body %lld"), count - known)))
            }
            seen.securityAlerts = count
        }

        return (alerts, seen)
    }

    /// Crashes newer than the newest one seen last time. The signature is the newest crash's
    /// date, so a backend that keeps only the last ten still reports each new one once.
    static func crashAlert(
        previous: Seen?, stats: RepoStats, repoID: Int, repoName: String, enabled: Set<Kind>
    ) -> (alert: Alert?, seen: Seen) {
        var seen = previous ?? Seen()
        let crashes = stats.issues.filter(\.isCrash).sorted { $0.at > $1.at }
        guard let newest = crashes.first else { return (nil, seen) }

        let signature = String(newest.at.timeIntervalSince1970)
        var alert: Alert?
        if enabled.contains(.crashes), let known = seen.crashSignature, let knownDate = TimeInterval(known) {
            let fresh = crashes.filter { $0.at.timeIntervalSince1970 > knownDate }
            let count = fresh.reduce(0) { $0 + max($1.count, 1) }
            if count > 0 {
                alert = Alert(
                    kind: .crashes, repoID: repoID,
                    title: String(format: String(localized: "alert_crash_title %@"), repoName),
                    body: String(format: String(localized: "alert_crash_body %lld"), count))
            }
        }
        seen.crashSignature = signature
        return (alert, seen)
    }
}

// MARK: - Center

/// Asks GitHub and the connected app backends again, in the background and on launch, and
/// posts a local notification for what changed: a build that went red, a release out, new
/// security alerts, new crashes. Pro only. Nothing leaves the device but the same requests the
/// home already makes.
@MainActor
final class RepoAlertCenter {
    static let shared = RepoAlertCenter()

    private static let seenKey = "repoAlertsSeen"

    private let defaults: UserDefaults
    private var seen: [Int: RepoAlertRules.Seen]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.seenKey),
           let stored = try? JSONDecoder().decode([Int: RepoAlertRules.Seen].self, from: data) {
            seen = stored
        } else {
            seen = [:]
        }
    }

    nonisolated deinit {}

    static func isEnabled(_ kind: RepoAlertRules.Kind) -> Bool {
        UserDefaults.standard.object(forKey: kind.defaultsKey) as? Bool ?? true
    }

    var enabledKinds: Set<RepoAlertRules.Kind> {
        Set(RepoAlertRules.Kind.allCases.filter(Self.isEnabled))
    }

    /// Refreshes and compares. Call after a sync, from the foreground or the background task.
    func check(repos: [ProjectRepo]) async {
        guard SubscriptionManager.shared.isPro else { return }
        let enabled = enabledKinds
        guard !enabled.isEmpty else { return }

        let live = repos.filter { !$0.isArchived && !$0.isLocal }
        let accounts = Array(Dictionary(grouping: live.compactMap(\.account)) { $0.id }.compactMap { $0.value.first })
        let activity = RepoActivityStore.shared
        await activity.refresh(repos: live, accounts: accounts, force: true)

        var alerts: [RepoAlertRules.Alert] = []
        for repo in live {
            if let facts = activity.activity(for: repo.repoID) {
                let result = RepoAlertRules.gitHubAlerts(
                    previous: seen[repo.repoID], activity: facts, repoName: repo.name, enabled: enabled)
                alerts.append(contentsOf: result.alerts)
                seen[repo.repoID] = result.seen
            }
            let stats = RepoStatsStore.shared
            if stats.isConfigured(repo.repoID) {
                await stats.refresh(repoID: repo.repoID, force: true)
                if let data = stats.stats(for: repo.repoID) {
                    let result = RepoAlertRules.crashAlert(
                        previous: seen[repo.repoID], stats: data, repoID: repo.repoID,
                        repoName: repo.name, enabled: enabled)
                    if let alert = result.alert { alerts.append(alert) }
                    seen[repo.repoID] = result.seen
                }
            }
        }
        save()
        await post(alerts)
    }

    private func post(_ alerts: [RepoAlertRules.Alert]) async {
        guard !alerts.isEmpty, await FeedbackNotificationManager.shared.requestAuthorizationIfNeeded() else { return }
        let center = UNUserNotificationCenter.current()
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "alert-\(alert.kind.rawValue)-\(alert.repoID)", content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(seen) else { return }
        defaults.set(data, forKey: Self.seenKey)
    }
}
