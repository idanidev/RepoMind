import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Bridges Home Screen Quick Actions (long-press the app icon) from the
/// UIApplicationDelegate layer into SwiftUI via NotificationCenter — the only
/// sanctioned cross-layer channel per the project's architecture rules.
@MainActor
final class QuickActionRouter {
    static let shared = QuickActionRouter()
    private init() {}

    static let quickAddTaskType = "com.idanidev.repomind.quickAddTask"

    #if canImport(UIKit)
    /// Set on cold launch (before the SwiftUI hierarchy exists to receive a notification).
    /// The root view consumes this once via `consumePendingIfNeeded()`.
    var pendingItem: UIApplicationShortcutItem?

    func handle(_ item: UIApplicationShortcutItem) {
        NotificationCenter.default.post(name: .quickActionTriggered, object: nil, userInfo: ["type": item.type])
    }

    func consumePendingIfNeeded() {
        guard let item = pendingItem else { return }
        pendingItem = nil
        handle(item)
    }
    #endif
}

extension Notification.Name {
    static let quickActionTriggered = Notification.Name("quickActionTriggered")
}
