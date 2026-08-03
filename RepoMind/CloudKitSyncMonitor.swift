import CoreData
import Foundation
import SwiftUI

/// Watches CloudKit mirroring and remembers when it last failed.
///
/// Without this the app is blind: `context.save()` succeeds locally whether or not the record ever
/// reaches iCloud, so a broken sync looks exactly like a working one. That is how this app shipped
/// a schema Production had never seen — nothing synced for months and there was no signal anywhere.
@MainActor
@Observable
final class CloudKitSyncMonitor {
    static let shared = CloudKitSyncMonitor()

    /// Message from the most recent failed import/export, cleared once a later one succeeds.
    private(set) var lastErrorMessage: String?
    private(set) var lastErrorDate: Date?
    private(set) var lastSuccessDate: Date?

    var hasSyncProblem: Bool { lastErrorMessage != nil }

    private var observer: NSObjectProtocol?

    private init() {}

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let event = notification.userInfo?[
                    NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                ] as? NSPersistentCloudKitContainer.Event
            else { return }
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        // Only completed events carry a verdict; ignore the "started" half.
        guard event.endDate != nil else { return }
        // Setup events fire on every launch and are noisy; only import/export matter to the user.
        guard event.type == .import || event.type == .export else { return }

        if let error = event.error {
            lastErrorMessage = error.localizedDescription
            lastErrorDate = event.endDate
            #if DEBUG
                print("[CloudKit] \(event.type) failed: \(error)")
            #endif
        } else {
            lastSuccessDate = event.endDate
            // A later success clears the warning — transient failures shouldn't nag forever.
            lastErrorMessage = nil
            lastErrorDate = nil
        }
    }
}
