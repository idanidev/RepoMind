import SwiftData
import SwiftUI

/// A dictation made outside a board (the widget, the shortcut, Siri, the Action Button): the
/// microphone, the drafts under review, and the filing of each one in the app it names.
///
/// The board has its own flow in `KanbanViewModel`; this is the same idea without a current repo.
/// Every draft carries the app it goes to, found in what was said, and the sheet asks for it
/// only when nothing said it.
@MainActor
@Observable
final class GlobalCaptureModel {
    private(set) var voiceManager = VoiceManager()
    private(set) var options: [CaptureRepoOption] = []
    /// The dictation under review, from the microphone stopping until Save or Discard.
    var capture: VoiceCapture?
    /// The microphone has been started at least once, which tells "heard nothing" from "not yet".
    private(set) var hasListened = false
    @ObservationIgnored private var composeTask: Task<Void, Never>?

    nonisolated deinit {}

    /// Whether the user wants the on-device model to shape captures. On by default.
    var shapesWithAI: Bool {
        UserDefaults.standard.object(forKey: "voiceAIEnabled") as? Bool ?? true
    }

    /// Every task has a title and, once the app is chosen, can be saved.
    var canSave: Bool {
        guard let capture else { return false }
        let filled = capture.drafts.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !filled.isEmpty && filled.allSatisfy { draft in options.contains { $0.id == draft.repoID } }
    }

    func columns(for draft: CaptureDraft) -> [String] {
        options.first { $0.id == draft.repoID }?.columns ?? []
    }

    /// The apps a task can go to: favorites first, then the rest as they come.
    static func options(from repos: [ProjectRepo]) -> [CaptureRepoOption] {
        let live = repos.filter { !$0.isArchived }
        return (live.filter(\.isFavorite) + live.filter { !$0.isFavorite }).map { repo in
            CaptureRepoOption(
                id: repo.repoID,
                name: repo.name,
                columns: (repo.columns ?? []).sorted { $0.orderIndex < $1.orderIndex }.map(\.name),
                ideaColumn: repo.ideaColumn?.name,
                isFavorite: repo.isFavorite)
        }
    }

    // MARK: Dictation

    /// Teaches the recognizer the names of every app and column, then starts listening: the way
    /// in was a tap on a microphone, so there is nothing else to press.
    func start(options: [CaptureRepoOption]) async {
        self.options = options
        voiceManager.contextualStrings = VoiceVocabulary.terms(
            repoNames: options.map(\.name), columns: options.flatMap(\.columns))
        await startListening()
    }

    func startListening() async {
        guard !voiceManager.isRecording else { return }
        hasListened = true
        await voiceManager.toggleRecording()
    }

    /// The microphone stopped, by hand, by silence or by "añadir a …": what it heard becomes the
    /// capture to review, or is appended to the one already open.
    func prepare() {
        let text = voiceManager.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        voiceManager.transcribedText = ""
        // "…, añadir a InSync" at the end is read by the recognizer as a column; here it is the app.
        let hint = voiceManager.detectedColumnName
        guard !text.isEmpty else { return }

        let transcript = capture.map { $0.transcript + "\n" + text } ?? text
        let useAI = shapesWithAI && VoiceComposer.isAvailable
        let opened = VoiceCapture(
            transcript: transcript,
            drafts: [GlobalCaptureRouting.fallbackDraft(transcript: transcript, options: options, hint: hint)],
            isComposing: useAI)
        capture = opened
        composeTask?.cancel()
        guard useAI else { return }

        let options = options
        let names = VoiceVocabulary.terms(repoNames: options.map(\.name), columns: [])
        composeTask = Task { [weak self] in
            let drafts = await VoiceComposer.composeGlobal(transcript: transcript, options: options, names: names)
            guard let self, !Task.isCancelled, capture?.id == opened.id else { return }
            if let drafts, !drafts.isEmpty {
                capture?.drafts = drafts
                capture?.composedByAI = true
            }
            capture?.isComposing = false
        }
    }

    func discard() {
        composeTask?.cancel()
        if voiceManager.isRecording { voiceManager.stopRecording() }
        voiceManager.transcribedText = ""
        capture = nil
    }

    // MARK: Saving

    /// Files each draft in its app, in the column it names or the first one (an idea goes to the
    /// ideas column when the app has one), and publishes it as an issue like any other task.
    /// Returns whether anything was saved.
    @discardableResult
    func save(repos: [ProjectRepo], context: ModelContext) -> Bool {
        guard let capture else { return false }
        composeTask?.cancel()

        var created: [(task: TaskItem, repo: ProjectRepo)] = []
        var nextOrder: [UUID: Int] = [:]
        for draft in capture.drafts where !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let repo = repos.first(where: { $0.repoID == draft.repoID }) else { continue }
            if (repo.columns ?? []).isEmpty {
                KanbanViewModel(project: repo, modelContext: context).initializeDefaultColumnsIfNeeded()
            }
            let ordered = (repo.columns ?? []).sorted { $0.orderIndex < $1.orderIndex }
            let column = ordered.first { $0.name == draft.columnName }
                ?? (draft.kind == .idea ? repo.ideaColumn : nil)
                ?? ordered.first
            guard let column else { continue }

            let order = nextOrder[column.id] ?? ((column.tasks ?? []).map(\.orderIndex).max() ?? -1) + 1
            nextOrder[column.id] = order + 1
            let task = TaskItem(
                content: draft.content,
                status: column.name.lowercased().replacingOccurrences(of: " ", with: "_"),
                column: column,
                project: repo,
                orderIndex: order)
            // Before the sync below reads them.
            TaskLabelStore.set(draft.labels, for: task.id)
            context.insert(task)
            created.append((task, repo))
        }
        guard !created.isEmpty else { return false }

        do {
            try context.save()
        } catch {
            // Never claim success for something that was not persisted.
            ToastManager.shared.show(String(localized: "task_save_failed"), style: .error)
            return false
        }

        let isDemo = UserDefaults.standard.bool(forKey: "isDemoMode")
        for entry in created where !isDemo && !entry.repo.isIdea(entry.task) {
            TaskIssueSyncService.shared.syncNewTaskInBackground(entry.task, repo: entry.repo, context: context)
        }

        var names: [String] = []
        for entry in created where !names.contains(entry.repo.name) {
            names.append(entry.repo.name)
        }
        let message = created.count == 1
            ? String(format: String(localized: "quick_add_task_created %@"), names.joined(separator: ", "))
            : String(
                format: String(localized: "global_capture_saved_many %lld %@"),
                created.count, names.joined(separator: ", "))
        ToastManager.shared.show(message, style: .success)
        self.capture = nil
        return true
    }
}
