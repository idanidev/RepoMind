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
        /// A version of one of the developer's apps went into review, was approved, rejected or published.
        case store

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
        /// `live|pending`: the published version, and the one on its way as `version:state`. Keyed in
        /// `RepoAlertCenter` by the negated Apple ID of the app, apart from the GitHub repo ids.
        var storeSignature: String?
    }

    struct Alert: Hashable {
        let kind: Kind
        let repoID: Int
        let title: String
        let body: String
    }

    /// Where a tap on the alert leads: the page on GitHub that has the answer (the failing run,
    /// the release, the security alerts), or the app's statistics for a crash. A repo with no
    /// GitHub page falls back to its board.
    static func target(for alert: Alert, htmlURL: String) -> NotificationTarget {
        let base = htmlURL.hasSuffix("/") ? String(htmlURL.dropLast()) : htmlURL
        func page(_ path: String) -> NotificationTarget {
            guard !base.isEmpty, let url = URL(string: base + path) else { return .board(repoID: alert.repoID) }
            return .web(url)
        }
        switch alert.kind {
        case .ci: return page("/actions")
        case .releases: return page("/releases/latest")
        case .security: return page("/security/dependabot")
        case .crashes: return .stats(repoID: alert.repoID)
        case .store:
            // For a store alert `repoID` is the app's Apple ID.
            guard let url = URL(string: "https://appstoreconnect.apple.com/apps/\(alert.repoID)/distribution")
            else { return .board(repoID: alert.repoID) }
            return .web(url)
        }
    }

    /// A change in what the App Store says about one app. The first sight is recorded, never announced.
    /// Published beats everything else; a version going into review, being approved or rejected each
    /// say so. Waiting for review and drafts are the developer's own doing, so they stay quiet.
    static func storeAlert(
        previous: Seen?, app: StoreStatus.StoreApp, name: String, enabled: Set<Kind>
    ) -> (alert: Alert?, seen: Seen) {
        var seen = previous ?? Seen()
        let release = app.primaryRelease
        let liveVersion = release?.live?.version ?? ""
        let pendingSignature = release?.pending.map { "\($0.version):\($0.state)" } ?? ""
        seen.storeSignature = "\(liveVersion)|\(pendingSignature)"
        guard enabled.contains(.store), let known = previous?.storeSignature else { return (nil, seen) }

        let parts = known.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let knownLive = parts.first ?? ""
        let knownPending = parts.count > 1 ? parts[1] : ""
        let appleID = Int(app.id) ?? 0

        if !liveVersion.isEmpty, liveVersion != knownLive {
            return (Alert(
                kind: .store, repoID: appleID,
                title: String(format: String(localized: "alert_store_live_title %@ %@"), name, liveVersion),
                body: String(localized: "alert_store_live_body")), seen)
        }
        guard let pending = release?.pending, "\(pending.version):\(pending.state)" != knownPending else {
            return (nil, seen)
        }
        let title: String
        let body: String
        switch pending.kind {
        case .inReview:
            title = String(format: String(localized: "alert_store_review_title %@ %@"), name, pending.version)
            body = String(localized: "alert_store_review_body")
        case .approved:
            title = String(format: String(localized: "alert_store_approved_title %@ %@"), name, pending.version)
            body = String(localized: "alert_store_approved_body")
        case .rejected:
            title = String(format: String(localized: "alert_store_rejected_title %@ %@"), name, pending.version)
            body = String(localized: "alert_store_rejected_body")
        default:
            return (nil, seen)
        }
        return (Alert(kind: .store, repoID: appleID, title: title, body: body), seen)
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
                    body: count - known == 1
                        ? String(localized: "alert_security_body_one")
                        : String(format: String(localized: "alert_security_body_other %lld"), count - known)))
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
            // One per crash that has news since, not the sum of their `count`: that is how many times
            // the crash happened in all, so a loop seen forty times would announce "40 crashes" on the
            // next hit of a crash already known.
            let count = crashes.filter { $0.at.timeIntervalSince1970 > knownDate }.count
            if count > 0 {
                alert = Alert(
                    kind: .crashes, repoID: repoID,
                    title: String(format: String(localized: "alert_crash_title %@"), repoName),
                    body: count == 1
                        ? String(localized: "alert_crash_body_one")
                        : String(format: String(localized: "alert_crash_body_other %lld"), count))
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
    private var isChecking = false

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

    /// Forgets what was seen, on sign-out: the next account's first sight is recorded, not announced.
    func reset() {
        seen = [:]
        defaults.removeObject(forKey: Self.seenKey)
    }

    static func isEnabled(_ kind: RepoAlertRules.Kind) -> Bool {
        UserDefaults.standard.object(forKey: kind.defaultsKey) as? Bool ?? true
    }

    var enabledKinds: Set<RepoAlertRules.Kind> {
        Set(RepoAlertRules.Kind.allCases.filter(Self.isEnabled))
    }

    /// What one key of `seen` becomes, and what has to be announced to get there.
    private struct Outcome {
        var seen: RepoAlertRules.Seen
        var alerts: [RepoAlertRules.Alert]
    }

    /// A repo as plain values: the models can be deleted while the requests are in the air (a sign-out,
    /// CloudKit removing a duplicate), and reading a deleted model is a fatal error.
    private struct RepoRef {
        let id: Int
        let name: String
        let htmlURL: String
    }

    /// Refreshes and compares. Call after a sync, from the foreground or the background task.
    ///
    /// Nothing is recorded as seen until it has been announced: a kill between the two, a notification
    /// permission that is off, or a failed `add` used to lose the alert for good while `seen` had
    /// already moved on. Keys with nothing to say are recorded at once; the others once the system has
    /// accepted every notification of that key. Stops quietly when its task is cancelled — the
    /// background refresh is cancelled when its time is up.
    func check(repos: [ProjectRepo]) async {
        guard SubscriptionManager.shared.isPro, !isChecking else { return }
        let enabled = enabledKinds
        guard !enabled.isEmpty else { return }
        isChecking = true
        defer { isChecking = false }

        let live = repos.filter { !$0.isArchived && !$0.isLocal }
        let refs = live.map { RepoRef(id: $0.repoID, name: $0.name, htmlURL: $0.htmlURL) }
        let accounts = Array(Dictionary(grouping: live.compactMap(\.account)) { $0.id }.compactMap { $0.value.first })
        // Plain values too, before anything is awaited: see `RepoRef`.
        let storeAccounts = accounts.map { StoreAccount(username: $0.username, tokenKey: $0.tokenKey) }
        let activity = RepoActivityStore.shared
        // Asked first and then waited for: a forced refresh while another one is running returns at once,
        // and waiting before asking would read the models again up to fifteen seconds later.
        await activity.refresh(repos: live, accounts: accounts, force: true)
        await activity.waitUntilIdle()

        var outcomes: [Int: Outcome] = [:]
        for repo in refs {
            if Task.isCancelled { return }
            var current = seen[repo.id]
            var alerts: [RepoAlertRules.Alert] = []
            if let facts = activity.activity(for: repo.id) {
                let result = RepoAlertRules.gitHubAlerts(
                    previous: current, activity: facts, repoName: repo.name, enabled: enabled)
                alerts.append(contentsOf: result.alerts)
                current = result.seen
            }
            let stats = RepoStatsStore.shared
            if stats.isConfigured(repo.id) {
                await stats.refresh(repoID: repo.id, force: true)
                if let data = stats.stats(for: repo.id) {
                    let result = RepoAlertRules.crashAlert(
                        previous: current, stats: data, repoID: repo.id, repoName: repo.name, enabled: enabled)
                    if let alert = result.alert { alerts.append(alert) }
                    current = result.seen
                }
            }
            if let current { outcomes[repo.id] = Outcome(seen: current, alerts: alerts) }
        }
        if Task.isCancelled { return }
        await checkStore(refs: refs, accounts: storeAccounts, outcomes: &outcomes)
        if Task.isCancelled { return }

        let htmlURLs = Dictionary(refs.map { ($0.id, $0.htmlURL) }, uniquingKeysWith: { first, _ in first })
        let pending = outcomes.filter { !$0.value.alerts.isEmpty }
        for (key, outcome) in outcomes where outcome.alerts.isEmpty {
            seen[key] = outcome.seen
        }
        let delivered = await post(pending.values.flatMap(\.alerts), htmlURLs: htmlURLs)
        for (key, outcome) in pending where outcome.alerts.allSatisfy(delivered.contains) {
            seen[key] = outcome.seen
        }
        save()
    }

    /// The App Store status, read again and compared like the rest. Its keys in `seen` are negative, so
    /// an Apple ID can never collide with a GitHub repo id.
    private func checkStore(
        refs: [RepoRef], accounts: [StoreAccount], outcomes: inout [Int: Outcome]
    ) async {
        let store = StoreStatusStore.shared
        guard store.isConfigured else { return }
        await store.refresh(accounts: accounts, force: true)
        guard let status = store.status else { return }
        let enabled = enabledKinds
        for app in status.apps {
            // An id that is not a number cannot be told apart from the next one: skip it.
            guard let appleID = Int(app.id), appleID > 0 else { continue }
            let key = -appleID
            let name = app.bestRepoName(in: refs.map(\.name)) ?? app.name
            let result = RepoAlertRules.storeAlert(previous: seen[key], app: app, name: name, enabled: enabled)
            outcomes[key] = Outcome(seen: result.seen, alerts: result.alert.map { [$0] } ?? [])
        }
    }

    /// The alerts the system accepted. Asks for the permission when it was never asked; with it off, or
    /// with `add` failing, an alert stays unseen and is worked out again at the next check.
    private func post(
        _ alerts: [RepoAlertRules.Alert], htmlURLs: [Int: String]
    ) async -> Set<RepoAlertRules.Alert> {
        guard !alerts.isEmpty, await FeedbackNotificationManager.shared.requestAuthorizationIfNeeded() else {
            return []
        }
        let center = UNUserNotificationCenter.current()
        var delivered: Set<RepoAlertRules.Alert> = []
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.body
            content.sound = .default
            content.threadIdentifier = "alerts-\(alert.repoID)"
            content.userInfo = RepoAlertRules.target(for: alert, htmlURL: htmlURLs[alert.repoID] ?? "").userInfo
            let request = UNNotificationRequest(
                identifier: "alert-\(alert.kind.rawValue)-\(alert.repoID)", content: content, trigger: nil)
            do {
                try await center.add(request)
                delivered.insert(alert)
            } catch {
                continue
            }
        }
        return delivered
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(seen) else { return }
        defaults.set(data, forKey: Self.seenKey)
    }
}
