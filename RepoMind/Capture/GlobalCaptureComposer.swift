import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

// MARK: - Routing

/// How a dictation made outside a board ends up as drafts, each with the app it goes to. The
/// part that decides is plain code, so it works on every iOS version and can be tested; the
/// on-device model, where there is one, only reads the dictation better.
enum GlobalCaptureRouting {
    /// The dictation as it came, filed under the app it names: "en InSync, arreglar el login"
    /// becomes the task "Arreglar el login" in InSync. With no app named, the draft has none and
    /// the sheet asks, unless there is only one app to choose from.
    ///
    /// In order: an app named as a prefix or a suffix (the phrase leaves the title); the app a trailing
    /// "…, añadir a X" asked for (`hint`); an app only mentioned in passing, as a guess. A passing
    /// mention used to win over the explicit command: "the widget of RepoMind … añadir a InSync" went
    /// to RepoMind.
    static func fallbackDraft(
        transcript: String, options: [CaptureRepoOption], hint: String? = nil
    ) -> CaptureDraft {
        var draft = CaptureDraft.fallback(transcript: transcript, columnName: nil)
        let found = CaptureRepoResolver.detect(in: transcript, options: options)
        if let found, found.stripped {
            if !found.rest.isEmpty { draft.title = found.rest }
            draft.repoID = found.option.id
        } else if let hint, let option = CaptureRepoResolver.match(hint, in: options) {
            draft.repoID = option.id
        } else if let found {
            draft.repoID = found.option.id
        } else if options.count == 1 {
            draft.repoID = options.first?.id
        }
        return draft
    }

    /// A draft from what the model said about one task. The app it named is matched to a real
    /// one; failing that, the app the dictation names; failing that, the only app there is. The
    /// column is looked up among the columns of that app, not of all of them.
    static func draft(
        title: String, details: String, kind: String, repo: String, column: String,
        transcript: String, options: [CaptureRepoOption]
    ) -> CaptureDraft {
        // What the dictation says goes first. The model's own pick only counts when the dictation mentions
        // that app in some form: a model that names one nobody said would otherwise pass for "the app was
        // said", and the sheet, which is meant to ask, would file the task there without a word.
        let named = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        let mentioned = CaptureRepoResolver.squash(transcript)
        let modelsPick = named.isEmpty ? nil : CaptureRepoResolver.match(named, in: options).flatMap { option in
            mentioned.contains(CaptureRepoResolver.squash(option.name)) ? option : nil
        }
        let option = CaptureRepoResolver.detect(in: transcript, options: options)?.option
            ?? modelsPick
            ?? (options.count == 1 ? options.first : nil)
        var draft = CaptureDraft(
            title: title, details: details, kind: kind, column: column,
            columns: option?.columns ?? [], ideaColumn: option?.ideaColumn)
        draft.repoID = option?.id
        return draft
    }
}

// MARK: - Composer

extension VoiceComposer {
    /// Shapes a dictation made outside a board into one or more drafts with the app each goes to.
    /// nil when the model is unavailable or failed: the caller keeps the fallback draft.
    static func composeGlobal(
        transcript: String, options: [CaptureRepoOption], names: [String]
    ) async -> [CaptureDraft]? {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, macCatalyst 26.0, macOS 26.0, *) {
                return try? await AICaptureComposer.composeGlobal(
                    transcript: transcript, options: options, names: names)
            }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
    @available(iOS 26.0, macCatalyst 26.0, macOS 26.0, *)
    @Generable
    struct ComposedGlobalCapture {
        @Guide(description: "One task per distinct subject in the dictation; usually just one")
        var tasks: [ComposedGlobalTask]
    }

    @available(iOS 26.0, macCatalyst 26.0, macOS 26.0, *)
    @Generable
    struct ComposedGlobalTask {
        @Guide(description: """
            Short imperative title, no filler words or repetition, in the language of the dictation, \
            at most 80 characters, without the phrase that names the app
            """)
        var title: String
        @Guide(description: """
            The rest of what was said, cleaned and ordered: context, steps, what done means. \
            Empty when the title says it all
            """)
        var details: String
        @Guide(description: "One of: bug, feature, idea, chore")
        var kind: String
        @Guide(description: """
            The exact name of the listed app the dictation says the task is for; empty if it names none
            """)
        var repo: String
        @Guide(description: "The exact name of one of that app's columns if the dictation names it; empty otherwise")
        var column: String
    }

    @available(iOS 26.0, macCatalyst 26.0, macOS 26.0, *)
    extension AICaptureComposer {
        static func composeGlobal(
            transcript: String, options: [CaptureRepoOption], names: [String]
        ) async throws -> [CaptureDraft] {
            let session = LanguageModelSession(instructions: globalInstructions(options: options, names: names))
            let response = try await session.respond(to: transcript, generating: ComposedGlobalCapture.self)
            return response.content.tasks
                .map {
                    GlobalCaptureRouting.draft(
                        title: $0.title, details: $0.details, kind: $0.kind, repo: $0.repo, column: $0.column,
                        transcript: transcript, options: options)
                }
                .filter { !$0.title.isEmpty }
        }

        private static func globalInstructions(options: [CaptureRepoOption], names: [String]) -> String {
            let apps = options
                .map { option in
                    let columns = option.columns.joined(separator: ", ")
                    return columns.isEmpty ? "- \(option.name)" : "- \(option.name): \(columns)"
                }
                .joined(separator: "\n")
            return """
                You turn a developer's dictated note into tasks for kanban boards, one board per app.
                The note was transcribed from speech: it may have filler words, repetitions, self-corrections \
                and wrong punctuation. Keep its meaning and its language; never translate, never invent facts.
                Usually the note is one task. Split it only when it clearly covers distinct subjects.
                The developer says which app a task is for: "in InSync, fix the login", "añade a RepoMind una \
                tarea para el widget", "arreglar el login en InSync". The apps, with their columns, are:
                \(apps)
                Put the exact name of the app in `repo` and leave the phrase that names it out of the title. \
                If the note names no app, leave `repo` empty; never guess. The transcription may have split or \
                misheard an app name ("in sync" for InSync, "repo mind" for RepoMind): match it to the listed app.
                Phrases like "add to X" or "move to X" name a column of that app; put its exact name in `column` \
                and leave it out of the title.
                Other names that may appear, spelled right: \(names.joined(separator: ", ")).
                Kind: bug for something broken, feature for something to build or improve, idea for a \
                loose thought that is not yet work, chore for maintenance.
                """
        }
    }
#endif
