import CloudKit
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
    /// What actually went wrong underneath, when the top-level error refuses to say.
    private(set) var lastErrorDetail: String?
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
            lastErrorDetail = detail(for: error)
            lastErrorDate = event.endDate
            #if DEBUG
                print("[CloudKit] \(event.type) failed: \(error)")
            #endif
        } else {
            lastSuccessDate = event.endDate
            // A later success clears the warning — transient failures shouldn't nag forever.
            lastErrorMessage = nil
            lastErrorDetail = nil
            lastErrorDate = nil
        }
    }

    // MARK: - Diagnosis

    /// Turns the error into something worth reading.
    ///
    /// `partialFailure` is the code CloudKit reports for "some records didn't make it", and its
    /// `localizedDescription` is the useless "operation could not be completed". Everything that
    /// identifies the actual problem sits in `partialErrorsByItemID`, one error per record, so it
    /// has to be dug out and summarised or the warning tells the user nothing they can act on.
    private func detail(for error: Error) -> String? {
        guard let ckError = error as? CKError else { return nil }

        let underlying: [CKError] =
            ckError.code == .partialFailure
            ? (ckError.partialErrorsByItemID?.values.compactMap { $0 as? CKError } ?? [])
            : [ckError]
        guard !underlying.isEmpty else { return nil }

        // Same cause repeated across 40 records is one problem, not forty.
        var counts: [CKError.Code: Int] = [:]
        for item in underlying { counts[item.code, default: 0] += 1 }

        return counts
            .sorted { $0.value > $1.value }
            .map { code, count in
                let text = explain(code)
                return count > 1 ? "\(text) (×\(count))" : text
            }
            .joined(separator: "\n")
    }

    /// The ones worth telling apart, because the fix differs. Anything else falls back to the raw
    /// code, which is still more use than "the operation could not be completed".
    private func explain(_ code: CKError.Code) -> String {
        switch code {
        case .quotaExceeded: return String(localized: "ck_error_quota")
        case .notAuthenticated: return String(localized: "ck_error_not_authenticated")
        case .networkUnavailable, .networkFailure: return String(localized: "ck_error_network")
        case .serverRecordChanged: return String(localized: "ck_error_conflict")
        case .unknownItem, .invalidArguments: return String(localized: "ck_error_schema")
        case .permissionFailure, .managedAccountRestricted:
            return String(localized: "ck_error_permission")
        case .zoneNotFound, .userDeletedZone: return String(localized: "ck_error_zone")
        case .limitExceeded: return String(localized: "ck_error_limit")
        default: return String(format: String(localized: "ck_error_other %lld"), code.rawValue)
        }
    }
}
