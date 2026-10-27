import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

// MARK: - Drafts

/// What a dictated note is about. Decides the default column (an idea goes to the ideas column)
/// and, later, the label the issue gets.
nonisolated enum CaptureKind: String, CaseIterable, Identifiable {
    case bug
    case feature
    case idea
    case chore

    var id: String { rawValue }

    /// What the chip and the picker call it.
    var title: String {
        switch self {
        case .bug: String(localized: "capture_kind_bug")
        case .feature: String(localized: "capture_kind_feature")
        case .idea: String(localized: "capture_kind_idea")
        case .chore: String(localized: "capture_kind_chore")
        }
    }

    var symbol: String {
        switch self {
        case .bug: "ant.fill"
        case .feature: "sparkles"
        case .idea: "lightbulb.fill"
        case .chore: "wrench.and.screwdriver.fill"
        }
    }
}

/// One task the capture will create, as the review sheet edits it.
struct CaptureDraft: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var details = ""
    var kind: CaptureKind = .feature
    /// The exact name of a column of the board, when the dictation named one or the kind
    /// implies one; nil means the column the board is showing.
    var columnName: String?
    /// Goes to the agent: the issue gets the `agent` label and the repo's workflow picks it up.
    var delegate = false
    /// `ProjectRepo.homeCardID` of the app it goes to. Only set when the capture starts outside a
    /// board (widget, Siri, the shortcut): on a board the app is the board's own, and nil.
    var repoID: String?

    var labels: TaskLabels { TaskLabels(kind: kind, delegated: delegate) }

    /// What goes into `TaskItem.content`: the title on the first line, which is what becomes the
    /// issue's title, and the details after a blank line, which the issue body carries whole.
    var content: String {
        let head = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? head : head + "\n\n" + detail
    }

    /// The dictation as it came, when nothing could give it shape.
    static func fallback(transcript: String, columnName: String?) -> CaptureDraft {
        CaptureDraft(title: transcript, columnName: columnName, delegate: TaskLabelStore.delegatesNewTasks)
    }

    /// From what the model answered, normalized: the kind parsed, the column matched to a real
    /// one by name (exact first, then contained), and an idea sent to the ideas column when the
    /// board has one and the dictation named none.
    init(
        title: String, details: String, kind: String, column: String, columns: [String], ideaColumn: String?
    ) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = CaptureKind(rawValue: kind.trimmingCharacters(in: .whitespaces).lowercased()) ?? .feature
        let wanted = column.trimmingCharacters(in: .whitespaces)
        var matched: String?
        if !wanted.isEmpty {
            matched = columns.first { $0.localizedCaseInsensitiveCompare(wanted) == .orderedSame }
                ?? columns.first { $0.localizedStandardContains(wanted) || wanted.localizedStandardContains($0) }
        }
        if matched == nil, self.kind == .idea {
            matched = ideaColumn
        }
        self.columnName = matched
        // An idea is not work yet: it never goes to the agent on its own.
        self.delegate = self.kind != .idea && TaskLabelStore.delegatesNewTasks
    }

    init(
        id: UUID = UUID(), title: String, details: String = "", kind: CaptureKind = .feature,
        columnName: String? = nil, delegate: Bool = false, repoID: String? = nil
    ) {
        self.id = id
        self.repoID = repoID
        self.title = title
        self.details = details
        self.kind = kind
        self.columnName = columnName
        self.delegate = delegate
    }
}

/// A recording turned into drafts, open in the review sheet until saved or discarded.
struct VoiceCapture: Identifiable {
    /// Stays the same while the capture is open, "keep dictating" included: the sheet is presented by
    /// this identity, and a new one dismissed it and presented it again.
    var id = UUID()
    /// Everything dictated, including what "keep dictating" added, separated by newlines.
    var transcript: String
    var drafts: [CaptureDraft]
    /// The on-device model is still working; the drafts shown are the fallback meanwhile.
    var isComposing: Bool
    var composedByAI = false
    /// Counts the dictations that have been added, so a late answer from the model can tell whether
    /// it is for the last one.
    var revision = 0
    /// The drafts as the app last made them (the raw dictation, or what the model shaped). Anything
    /// different is something the person changed.
    private(set) var baseline: [CaptureDraft]
    private var sawEdits = false

    init(transcript: String, drafts: [CaptureDraft], isComposing: Bool) {
        self.transcript = transcript
        self.drafts = drafts
        self.isComposing = isComposing
        self.baseline = drafts
    }

    /// Whether the person has edited, picked or removed anything since the app made the drafts, and
    /// stays true from the first time: later dictation must not wipe it.
    var hasUserEdits: Bool { sawEdits || drafts != baseline }

    /// "Keep dictating" with nothing edited: the new text joins the transcript and everything is
    /// worked out again from the whole of it.
    mutating func recompute(transcript: String, drafts: [CaptureDraft], isComposing: Bool) {
        self.transcript = transcript
        self.drafts = drafts
        self.baseline = drafts
        self.isComposing = isComposing
        composedByAI = false
        sawEdits = false
        revision += 1
    }

    /// "Keep dictating" after the person edited something: the new text becomes a draft of its own and
    /// what they changed stays. Recomputing from the whole transcript rebuilt every card from scratch,
    /// losing every title they had fixed and every app or column they had picked.
    mutating func append(segment: CaptureDraft, text: String, isComposing: Bool) {
        if drafts != baseline { sawEdits = true }
        transcript += "\n" + text
        drafts.append(segment)
        self.isComposing = isComposing
        revision += 1
    }

    /// Puts the model's drafts in the place of `snapshot`, but only when those drafts are still exactly
    /// as they were when the model was asked: if the person edited the title, picked another app or kind,
    /// or removed a card while "Giving it shape…" was showing, the model's answer is dropped and their
    /// work stays. Returns whether it was applied.
    @discardableResult
    mutating func applyComposed(_ composed: [CaptureDraft], replacing snapshot: [CaptureDraft]) -> Bool {
        if drafts != baseline { sawEdits = true }
        let ids = Set(snapshot.map(\.id))
        let current = drafts.filter { ids.contains($0.id) }
        guard !composed.isEmpty, current == snapshot, let first = drafts.firstIndex(where: { ids.contains($0.id) })
        else { return false }
        drafts.removeAll { ids.contains($0.id) }
        drafts.insert(contentsOf: composed, at: min(first, drafts.count))
        composedByAI = true
        baseline = drafts
        return true
    }
}

// MARK: - Adding a dictation

extension VoiceCapture {
    /// What a finished dictation does to the capture under review, shared by the board and the global
    /// sheet so the two behave the same.
    struct Addition {
        var capture: VoiceCapture
        /// The drafts the model's answer may replace.
        var target: [CaptureDraft]
        /// The text the model is asked to shape.
        var dictated: String
    }

    /// Starts a capture from `text`, or adds it to `open`. Nothing touched yet: the new text joins the
    /// transcript and everything is worked out again from the whole of it. Something edited: the new
    /// text becomes a card of its own, so what the person changed stays. `draft` makes the raw card for
    /// a piece of text (the board and the global sheet route it differently).
    static func adding(
        _ text: String, to open: VoiceCapture?, isComposing: Bool, draft: (String) -> CaptureDraft
    ) -> Addition {
        guard var open else {
            let whole = draft(text)
            return Addition(
                capture: VoiceCapture(transcript: text, drafts: [whole], isComposing: isComposing),
                target: [whole], dictated: text)
        }
        if open.hasUserEdits {
            let segment = draft(text)
            open.append(segment: segment, text: text, isComposing: isComposing)
            return Addition(capture: open, target: [segment], dictated: text)
        }
        let transcript = open.transcript + "\n" + text
        let whole = draft(transcript)
        open.recompute(transcript: transcript, drafts: [whole], isComposing: isComposing)
        return Addition(capture: open, target: [whole], dictated: transcript)
    }
}

// MARK: - Vocabulary

/// Words the recognizer would otherwise mangle: the names of the user's repos and apps, the
/// developer's everyday terms, and whatever they add in Settings → Voice. Handed to the speech
/// recognizer as contextual strings and to the model so it keeps the spelling.
enum VoiceVocabulary {
    static let developerTerms = [
        "RepoMind", "GitHub", "TestFlight", "App Store", "App Store Connect", "Xcode", "SwiftUI", "SwiftData",
        "CloudKit", "iCloud", "Supabase", "Firebase", "widget", "commit", "pull request", "merge", "release",
        "backend", "frontend", "API", "token", "login", "onboarding", "paywall", "Face ID", "Catalyst",
    ]

    /// Comma- or newline-separated, from Settings.
    static var customTerms: [String] {
        let raw = UserDefaults.standard.string(forKey: "voiceCustomVocabulary") ?? ""
        return raw.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The repos of the same account first: those are the names most likely to be said.
    static func names(for project: ProjectRepo) -> [String] {
        var names = [project.name]
        names.append(contentsOf: (project.account?.repos ?? []).map(\.name))
        names.append(contentsOf: customTerms)
        return unique(names)
    }

    static func terms(for project: ProjectRepo) -> [String] {
        Array(unique(names(for: project) + developerTerms).prefix(120))
    }

    /// Outside a board there is no current repo: every app's name goes first, then the columns
    /// the recognizer will hear as well.
    static func terms(repoNames: [String], columns: [String]) -> [String] {
        Array(unique(repoNames + customTerms + columns + developerTerms).prefix(120))
    }

    private static func unique(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        return terms.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}

// MARK: - Composer

/// Gives a dictation its shape with the on-device model, on iOS 26 and a device that has it.
/// Anywhere else `compose` answers nil and the dictation is saved as it came, like before.
enum VoiceComposer {
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, macCatalyst 26.0, macOS 26.0, *) {
                return AICaptureComposer.isAvailable
            }
        #endif
        return false
    }

    /// nil when the model is unavailable or failed: the caller keeps the fallback draft.
    static func compose(
        transcript: String, columns: [String], ideaColumn: String?, names: [String]
    ) async -> [CaptureDraft]? {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, macCatalyst 26.0, macOS 26.0, *) {
                return try? await AICaptureComposer.compose(
                    transcript: transcript, columns: columns, ideaColumn: ideaColumn, names: names)
            }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
    @available(iOS 26.0, macCatalyst 26.0, macOS 26.0, *)
    @Generable
    struct ComposedCapture {
        @Guide(description: "One task per distinct subject in the dictation; usually just one")
        var tasks: [ComposedTask]
    }

    @available(iOS 26.0, macCatalyst 26.0, macOS 26.0, *)
    @Generable
    struct ComposedTask {
        @Guide(description: """
            Short imperative title, no filler words or repetition, in the language of the dictation, \
            at most 80 characters
            """)
        var title: String
        @Guide(description: """
            The rest of what was said, cleaned and ordered: context, steps, what done means. \
            Empty when the title says it all
            """)
        var details: String
        @Guide(description: "One of: bug, feature, idea, chore")
        var kind: String
        @Guide(description: "The exact name of one of the listed columns if the dictation names it; empty otherwise")
        var column: String
    }

    @available(iOS 26.0, macCatalyst 26.0, macOS 26.0, *)
    enum AICaptureComposer {
        static var isAvailable: Bool {
            if case .available = SystemLanguageModel.default.availability { return true }
            return false
        }

        static func compose(
            transcript: String, columns: [String], ideaColumn: String?, names: [String]
        ) async throws -> [CaptureDraft] {
            let session = LanguageModelSession(instructions: instructions(columns: columns, names: names))
            let response = try await session.respond(to: transcript, generating: ComposedCapture.self)
            return response.content.tasks
                .map {
                    CaptureDraft(
                        title: $0.title, details: $0.details, kind: $0.kind, column: $0.column,
                        columns: columns, ideaColumn: ideaColumn)
                }
                .filter { !$0.title.isEmpty }
        }

        /// The model gets the board's columns and the rules; the dictation itself is the prompt.
        private static func instructions(columns: [String], names: [String]) -> String {
            """
            You turn a developer's dictated note about their own app into tasks for a kanban board.
            The note was transcribed from speech: it may have filler words, repetitions, self-corrections \
            and wrong punctuation. Keep its meaning and its language; never translate, never invent facts.
            Usually the note is one task. Split it only when it clearly covers distinct subjects.
            The board's columns are: \(columns.joined(separator: ", ")). Phrases like "add to X" or \
            "move to X" name a column; put its exact name in `column` and leave it out of the title.
            Product and repository names that may appear, spelled right: \(names.joined(separator: ", ")). \
            The transcription may have misheard them; use these spellings.
            Kind: bug for something broken, feature for something to build or improve, idea for a \
            loose thought that is not yet work, chore for maintenance.
            """
        }
    }
#endif

// MARK: - Board flow

extension KanbanViewModel {
    private var columnNames: [String] {
        (project.columns ?? []).sorted { $0.orderIndex < $1.orderIndex }.map(\.name)
    }

    /// Whether the user wants the on-device model to shape captures. On by default.
    var shapesCapturesWithAI: Bool {
        UserDefaults.standard.object(forKey: "voiceAIEnabled") as? Bool ?? true
    }

    /// Turns what the microphone heard into a capture to review. With one already open, "keep
    /// dictating" lands here too. If nothing was touched, the new text is appended and everything is
    /// worked out again from the whole dictation; if the person has edited a card, the new text becomes a
    /// card of its own and what they changed stays.
    func prepareCapture() {
        let text = voiceManager.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        voiceManager.transcribedText = ""
        guard !text.isEmpty else { return }

        let routed = voiceManager.detectedColumnName.flatMap { detected in
            columnNames.first { $0.localizedCaseInsensitiveCompare(detected) == .orderedSame }
                ?? columnNames.first { $0.localizedStandardContains(detected) }
        }
        let useAI = shapesCapturesWithAI && VoiceComposer.isAvailable

        let addition = VoiceCapture.adding(text, to: pendingCapture, isComposing: useAI) {
            CaptureDraft.fallback(transcript: $0, columnName: routed)
        }
        let target = addition.target
        let dictated = addition.dictated
        pendingCapture = addition.capture
        composeTask?.cancel()
        guard useAI else { return }

        let id = addition.capture.id
        let revision = addition.capture.revision
        let columns = columnNames
        let idea = project.ideaColumn?.name
        let names = VoiceVocabulary.names(for: project)
        composeTask = Task { [weak self] in
            let drafts = await VoiceComposer.compose(
                transcript: dictated, columns: columns, ideaColumn: idea, names: names)
            guard let self, !Task.isCancelled, pendingCapture?.id == id, pendingCapture?.revision == revision
            else { return }
            if let drafts, !drafts.isEmpty {
                // "…, añadir a Hecho" was taken out of the text before the model saw it, so the column
                // it named is put back here; the model is only asked for the ones it hears itself.
                let filled = drafts.map { draft -> CaptureDraft in
                    var draft = draft
                    if draft.columnName == nil { draft.columnName = routed }
                    return draft
                }
                pendingCapture?.applyComposed(filled, replacing: target)
            }
            pendingCapture?.isComposing = false
        }
    }

    /// One task per draft, in the column it names or the one the board is showing.
    func saveCapture() {
        guard let capture = pendingCapture else { return }
        composeTask?.cancel()
        stopDictating()
        let ordered = (project.columns ?? []).sorted { $0.orderIndex < $1.orderIndex }
        for draft in capture.drafts where !draft.title.trimmingCharacters(in: .whitespaces).isEmpty {
            let column = draft.columnName.flatMap { name in ordered.first { $0.name == name } }
                ?? currentColumn
                ?? ordered.first
            guard let column else { continue }
            createTask(content: draft.content, column: column, labels: draft.labels)
        }
        pendingCapture = nil
    }

    func discardCapture() {
        composeTask?.cancel()
        stopDictating()
        pendingCapture = nil
    }

    /// The microphone may still be open — "keep dictating" and then Save or Discard — and whatever it
    /// hears next would reopen the sheet as a capture nobody asked for.
    private func stopDictating() {
        if voiceManager.isRecording { voiceManager.stopRecording(immediately: true) }
        voiceManager.transcribedText = ""
    }
}
