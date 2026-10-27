import Foundation
import SwiftData

/// What signing out must forget besides the SwiftData rows: the tokens in the Keychain (every
/// account's and the one per connected app, all of them synced through iCloud Keychain), and the
/// caches and checkpoints the stores keep in `UserDefaults`.
///
/// Sign-out used to delete one Keychain item under a key no account uses (`github-pat`), so the real
/// tokens stayed on every device, and the next account on the phone inherited the previous one's
/// activity, alerts "already seen", app statistics and App Store status.
@MainActor
enum SessionReset {
    static func run(context: ModelContext) async {
        // Feedback rows hang off a repo name, not a relationship, so deleting the repos leaves them.
        try? context.delete(model: FeedbackIssue.self)

        await RepoStatsStore.shared.disconnectAll()
        StoreStatusStore.shared.disconnect()
        RepoActivityStore.shared.reset()
        RepoAlertCenter.shared.reset()
        FeedbackService.shared.resetCheckpoints()
        TaskLabelStore.removeAll()

        try? await KeychainManager.shared.deleteAllTokens()
    }
}
