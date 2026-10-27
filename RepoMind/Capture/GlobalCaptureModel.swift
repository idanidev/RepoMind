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

    /// The apps a task can go to: favorites first, then the rest as they come. A free account gets the
    /// ones its home shows (`limit`), not every repo it has synced.
    static func options(from repos: [ProjectRepo], limit: Int? = nil) -> [CaptureRepoOption] {
        let live = repos.filter { !$0.isArchived }
        let ordered = live.filter(\.isFavorite) + live.filter { !$0.isFavorite }
        return ordered.prefix(limit ?? ordered.count).map { repo in
            CaptureRepoOption(
                id: repo.homeCardID,
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
        refreshOptions(options)
        voiceManager.contextualStrings = VoiceVocabulary.terms(
            repoNames: options.map(\.name), columns: options.flatMap(\.columns))
        await startListening()
    }

    /// The apps changed under an open sheet (CloudKit delivering repos late, a favorite starred): the
    /// list the drafts are checked against follows, and "añadir a …" can name the new ones.
    func refreshOptions(_ options: [CaptureRepoOption]) {
        self.options = options
        voiceManager.routingNames = options.map(\.name)
    }

    func startListening() async {
        guard !voiceManager.isRecording else { return }
        await voiceManager.toggleRecording()
        // After, not before: while the permission prompt is up this is still "not yet", and it was
        // reading "I didn't hear anything" behind the prompt.
        hasListened = true
    }

    /// The microphone stopped, by hand, by silence or by "añadir a …": what it heard becomes the
    /// capture to review, or is added to the one already open.
    func prepare() {
        let text = voiceManager.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        voiceManager.transcribedText = ""
        // "…, añadir a InSync" at the end is read by the recognizer as a column; here it is the app.
        let hint = voiceManager.detectedColumnName
        guard !text.isEmpty else { return }

        let options = options
        let hinted = hint.flatMap { CaptureRepoResolver.match($0, in: options) }
        let useAI = shapesWithAI && VoiceComposer.isAvailable
        let addition = VoiceCapture.adding(text, to: capture, isComposing: useAI) {
            GlobalCaptureRouting.fallbackDraft(transcript: $0, options: options, hint: hint)
        }
        capture = addition.capture
        composeTask?.cancel()
        guard useAI else { return }

        let id = addition.capture.id
        let revision = addition.capture.revision
        let target = addition.target
        let dictated = addition.dictated
        let names = VoiceVocabulary.terms(repoNames: options.map(\.name), columns: [])
        composeTask = Task { [weak self] in
            let drafts = await VoiceComposer.composeGlobal(transcript: dictated, options: options, names: names)
            guard let self, !Task.isCancelled, capture?.id == id, capture?.revision == revision else { return }
            if let drafts, !drafts.isEmpty {
                let filled = drafts.map {
                    Self.settingApp($0, named: hinted?.id, fallback: target.first?.repoID)
                }
                capture?.applyComposed(filled, replacing: target)
            }
            capture?.isComposing = false
        }
    }

    /// "…, añadir a InSync" was taken out of the text before the model saw it, so the app it named is put
    /// back here, over the model's own guess. Failing that, the one the raw draft found.
    nonisolated static func settingApp(
        _ draft: CaptureDraft, named hinted: String?, fallback: String?
    ) -> CaptureDraft {
        var draft = draft
        if let hinted {
            draft.repoID = hinted
        } else if draft.repoID == nil {
            draft.repoID = fallback
        }
        return draft
    }

    func discard() {
        composeTask?.cancel()
        if voiceManager.isRecording { voiceManager.stopRecording(immediately: true) }
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
        if voiceManager.isRecording { voiceManager.stopRecording(immediately: true) }
        voiceManager.transcribedText = ""

        var created: [(task: TaskItem, repo: ProjectRepo)] = []
        var nextOrder: [UUID: Int] = [:]
        for draft in capture.drafts where !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Only the apps the sheet offered: a draft can carry the id of one a free account cannot see.
            guard options.contains(where: { $0.id == draft.repoID }),
                let repo = repos.first(where: { $0.homeCardID == draft.repoID })
            else { continue }
            KanbanViewModel.createDefaultColumnsIfNeeded(for: repo, in: context)
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
            // Never claim success for something that was not persisted. And do not leave the tasks
            // inserted: the capture stays open, and the next Save, or the autosave, would write them
            // twice.
            for entry in created {
                TaskLabelStore.remove(for: entry.task.id)
                context.delete(entry.task)
            }
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
