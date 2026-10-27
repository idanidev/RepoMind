import AppIntents
import Foundation

// MARK: - Router

/// How the app learns that something outside it (the widget, Siri, the shortcut, the Action
/// Button, a `repomind://capture` link) wants the dictation sheet open.
///
/// The request can arrive before the interface exists, on a cold launch from Siri, so it is kept
/// until something consumes it; a notification tells a running interface to look. NotificationCenter
/// is allowed here because the request crosses layers, which is what the architecture rules keep it for.
@MainActor
final class GlobalCaptureRouter {
    static let shared = GlobalCaptureRouter()
    /// Not private so a test can have its own: the shared one is wired to the running interface.
    init() {}

    /// An instance that dies, like the test's, would otherwise abort in the synthesized deinit
    /// (swiftlang/swift#85663, see CLAUDE.md).
    nonisolated deinit {}

    private var isPending = false

    func request() {
        isPending = true
        NotificationCenter.default.post(name: .globalCaptureRequested, object: nil)
    }

    /// True once per request.
    func consumePending() -> Bool {
        defer { isPending = false }
        return isPending
    }
}

extension Notification.Name {
    static let globalCaptureRequested = Notification.Name("globalCaptureRequested")
}

// MARK: - Shortcut

/// "Add a task in RepoMind": opens the app on the dictation sheet. The listening and the choice
/// of app happen there, by voice, so the shortcut itself takes no parameters.
///
/// It is also what the Action Button, a Lock Screen or Control Center "Shortcut" control and
/// Spotlight run.
nonisolated struct CaptureTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "intent_capture_title"
    static let description = IntentDescription("intent_capture_description")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        GlobalCaptureRouter.shared.request()
        return .result()
    }
}

nonisolated struct RepoMindShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureTaskIntent(),
            phrases: [
                "Add a task in \(.applicationName)",
                "Dictate a task in \(.applicationName)",
                "New task in \(.applicationName)",
                "Capture in \(.applicationName)",
            ],
            shortTitle: "intent_capture_short_title",
            systemImageName: "mic.fill")
    }
}
