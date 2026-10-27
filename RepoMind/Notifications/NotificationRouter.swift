import Foundation
import Observation
import UserNotifications

// MARK: - Router

/// The tap on a notification, waiting for a screen to take it.
///
/// A tap can arrive before the interface exists (a cold launch) or before the repos have come
/// down from iCloud, so the target is kept until the home or the iPad list can resolve it, and
/// cleared only then.
@MainActor
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()

    private(set) var pending: NotificationTarget?

    private init() {}

    func open(_ target: NotificationTarget) {
        pending = target
    }

    func clear() {
        pending = nil
    }
}

// MARK: - Delegate

/// Receives the taps, and decides that a notification shows as a banner even with the app open.
///
/// Without a delegate a tap only launches the app, and a notification posted while the app is in
/// the foreground is never shown: that is how the issue notifications ended up opening nothing.
/// Set in `application(_:didFinishLaunchingWithOptions:)`, because a tap that launches the app is
/// delivered as soon as the delegate is set.
nonisolated final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // The sound already played when the app was in the background; with the app open the
        // banner is enough.
        [.banner, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            let target = NotificationTarget.parse(response.notification.request.content.userInfo)
        else { return }
        await MainActor.run { NotificationRouter.shared.open(target) }
    }
}
