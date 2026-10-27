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

    var labels: TaskLabels { TaskLabels(kind: kind, delegated: delegate) }

    /// What goes into `TaskItem.content`: the title on the first line, which is what becomes the
    /// issue's title, and the details after a blank line, which the issue body carries whole.
    var content: String {
        let detail = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? title : title + "\n\n" + detail
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
        columnName: String? = nil, delegate: Bool = false
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.kind = kind
        self.columnName = columnName
        self.delegate = delegate
    }
}

/// A recording turned into drafts, open in the review sheet until saved or discarded.
struct VoiceCapture: Identifiable {
    let id = UUID()
    /// Everything dictated, including what "keep dictating" added, separated by newlines.
    var transcript: String
    var drafts: [CaptureDraft]
    /// The on-device model is still working; the drafts shown are the fallback meanwhile.
    var isComposing: Bool
    var composedByAI = false
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
    /// dictating" lands here too: the new text is appended and the drafts are recomputed.
    func prepareCapture() {
        let text = voiceManager.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        voiceManager.transcribedText = ""
        guard !text.isEmpty else { return }

        let transcript = pendingCapture.map { $0.transcript + "\n" + text } ?? text
        let routed = voiceManager.detectedColumnName.flatMap { detected in
            columnNames.first { $0.localizedStandardContains(detected) }
        }
        let useAI = shapesCapturesWithAI && VoiceComposer.isAvailable
        let capture = VoiceCapture(
            transcript: transcript,
            drafts: [CaptureDraft.fallback(transcript: transcript, columnName: routed)],
            isComposing: useAI)
        pendingCapture = capture
        composeTask?.cancel()
        guard useAI else { return }

        let columns = columnNames
        let idea = project.ideaColumn?.name
        let names = VoiceVocabulary.names(for: project)
        composeTask = Task { [weak self] in
            let drafts = await VoiceComposer.compose(
                transcript: transcript, columns: columns, ideaColumn: idea, names: names)
            guard let self, !Task.isCancelled, pendingCapture?.id == capture.id else { return }
            if let drafts, !drafts.isEmpty {
                pendingCapture?.drafts = drafts
                pendingCapture?.composedByAI = true
            }
            pendingCapture?.isComposing = false
        }
    }

    /// One task per draft, in the column it names or the one the board is showing.
    func saveCapture() {
        guard let capture = pendingCapture else { return }
        composeTask?.cancel()
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
        pendingCapture = nil
    }
}
