import StoreKit
import SwiftUI

/// Asks for an App Store rating, once, after something has actually gone well.
///
/// Nothing in the app ever asked. Happy users do not think to go and rate an app; people with a
/// problem do — so an unprompted rating average gets written almost entirely by the ones who had
/// a bad time.
///
/// `requestReview` is rationed by the system: roughly three prompts per user per year, and the
/// dialog may simply not appear at all. That budget is worth spending carefully, which is why this
/// waits for a moment of success — tasks being completed — instead of firing on launch, and why it
/// asks only once per app version.
@MainActor
enum ReviewPrompter {
    private static let countKey = "completedTaskCount"
    private static let versionKey = "lastReviewPromptVersion"

    /// How much use has to happen first. Low enough to catch people while they are still engaged,
    /// high enough that nobody is asked before the app has done anything for them.
    private static let threshold = 5

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Call when a task reaches the done column, or when a coding agent closes one.
    static func recordCompletedTask() {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: countKey) + 1
        defaults.set(count, forKey: countKey)
        guard count >= threshold else { return }
        askIfAppropriate()
    }

    /// Never twice for the same version: someone who dismissed the prompt has already answered,
    /// and asking again the same week is how an app earns the rating it was trying to avoid.
    private static func askIfAppropriate() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: versionKey) != currentVersion else { return }
        // Demo mode is a tour, not use. Asking there would spend the yearly budget on someone who
        // has not even signed in.
        guard !defaults.bool(forKey: "isDemoMode") else { return }

        #if !targetEnvironment(macCatalyst)
            guard
                let scene = UIApplication.shared.connectedScenes
                    .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
            else { return }
            AppStore.requestReview(in: scene)
            defaults.set(currentVersion, forKey: versionKey)
        #endif
    }
}
