import Foundation

// MARK: - Options

/// A board a capture can be filed in, as the resolver and the model see it: plain values, no
/// SwiftData, so the routing can be tested without a store.
nonisolated struct CaptureRepoOption: Hashable, Sendable, Identifiable {
    /// `ProjectRepo.homeCardID`, the identity the home already uses. Not `repoID`: every local project
    /// and every repo restored from a backup has a `repoID` of zero, so two of them were one option and
    /// a task meant for the second was filed in the first.
    var id: String
    var name: String
    /// The board's columns in order; empty for a repo that has not opened its board yet.
    var columns: [String] = []
    var ideaColumn: String?
    var isFavorite = false
}

// MARK: - Resolver

/// Works out which app a dictation is for. The speech recognizer writes "in sync" for InSync and
/// "repo mind" for RepoMind, and people say "en InSync, arreglar el login" or "arreglar el login
/// en InSync", so names are compared ignoring case, accents, punctuation and spaces.
nonisolated enum CaptureRepoResolver {
    /// The app a dictation names, and what is left once the naming phrase is taken out.
    nonisolated struct Detection: Equatable {
        var option: CaptureRepoOption
        /// The dictation without "en InSync" when the app was named as a prefix or a suffix;
        /// the dictation as it came when the app was only mentioned in passing.
        var rest: String
        /// Whether `rest` is shorter than the dictation.
        var stripped: Bool
    }

    /// Lowercase, no accents, every run of anything but letters and digits as one space:
    /// "In-Sync!" becomes "in sync".
    static func fold(_ text: String) -> String {
        let plain = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var result = ""
        var pendingSpace = false
        for character in plain {
            if character.isLetter || character.isNumber {
                if pendingSpace, !result.isEmpty { result.append(" ") }
                pendingSpace = false
                result.append(character)
            } else {
                pendingSpace = true
            }
        }
        return result
    }

    /// `fold` with the spaces gone, where "in sync" and "InSync" meet.
    static func squash(_ text: String) -> String {
        fold(text).replacingOccurrences(of: " ", with: "")
    }

    /// The option a name refers to: the exact name first, then a name that contains it or is
    /// contained by it when that picks exactly one. `api` must not file a task under `api-legacy`
    /// when both exist, so an ambiguous name answers nil and the user chooses.
    static func match(_ spoken: String, in options: [CaptureRepoOption]) -> CaptureRepoOption? {
        let key = squash(spoken)
        guard key.count >= 2 else { return nil }
        if let exact = options.first(where: { squash($0.name) == key }) { return exact }
        let partial = options.filter {
            let name = squash($0.name)
            return name.count >= 3 && (name.contains(key) || key.contains(name))
        }
        return partial.count == 1 ? partial.first : nil
    }

    // MARK: Detection

    private static let prepositions: Set<String> = [
        "en", "a", "para", "in", "to", "for", "on", "into", "app", "aplicacion", "repo", "repositorio",
        "proyecto", "project",
    ]

    /// What a person says before naming the app: "añade una tarea en InSync". When everything before
    /// the preposition is one of these, the phrase is a command and goes away with the name.
    private static let commandWords: Set<String> = [
        "anade", "anadir", "agrega", "agregar", "apunta", "apuntar", "anota", "anotar", "crea", "crear",
        "pon", "poner", "mete", "meter", "guarda", "guardar", "nueva", "nuevo", "una", "un", "tarea",
        "tareas", "nota", "idea", "bug", "incidencia", "issue", "add", "create", "new", "note", "task",
        "an", "a", "the", "please", "por", "favor", "oye", "vale", "ok", "quiero", "quisiera", "necesito",
        "me", "te", "puedes", "podrias", "hay", "que", "la", "el", "de", "of", "app", "repo",
    ]

    /// What can sit between the end of the task and the name once the preposition is found: "en la app
    /// InSync", "del proyecto RepoMind", "to the repo InSync". All of it goes with the name; stopping at
    /// the article left the task ending in a dangling "en" or "del".
    private static let linkWords: Set<String> = [
        "la", "el", "the", "app", "aplicacion", "repo", "repositorio", "proyecto", "project", "de", "del", "al",
        "of", "en", "in", "a", "para", "for", "to", "on", "into",
    ]

    private nonisolated struct Hit {
        var option: CaptureRepoOption
        /// Word indexes of the name, `end` exclusive.
        var start: Int
        var end: Int
    }

    /// Finds the app a dictation names, longest names first so "api legacy" wins over "api".
    ///
    /// - Named at the start ("en InSync, arreglar el login", "añade una tarea en InSync arreglar
    ///   el login", "InSync: arreglar el login") or at the end ("arreglar el login en InSync"):
    ///   that phrase is taken out of the text.
    /// - Mentioned once in the middle ("el widget de RepoMind no carga"): the text stays, since it
    ///   is part of what was said, and the app is only the guess.
    /// - Two different apps mentioned, or none: nil.
    static func detect(in transcript: String, options: [CaptureRepoOption]) -> Detection? {
        let words = transcript.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        let cleaned = words.map(fold)
        let hits = findHits(words: words, cleaned: cleaned, options: options)
        guard !hits.isEmpty else { return nil }

        for hit in hits {
            let cue = cueStart(for: hit, cleaned: cleaned)
            if let cue, cleaned[..<cue].allSatisfy({ commandWords.contains($0) || $0.isEmpty }) {
                return Detection(option: hit.option, rest: tidy(words[hit.end...]), stripped: true)
            }
            if cue == nil, hit.start == 0, endsSentence(words[hit.end - 1]) {
                return Detection(option: hit.option, rest: tidy(words[hit.end...]), stripped: true)
            }
            if let cue, trailingFiller(cleaned, after: hit.end) {
                return Detection(option: hit.option, rest: tidy(words[..<cue]), stripped: true)
            }
        }

        let distinct = Set(hits.map(\.option.id))
        guard distinct.count == 1, let first = hits.first, squash(first.option.name).count >= 3 else { return nil }
        return Detection(option: first.option, rest: transcript, stripped: false)
    }

    /// Every place a name appears, one to three words long, longest names first. A name never spans a
    /// comma or a colon: "En InSync, web: arreglar el login" is the app InSync, not "InSync Web".
    private static func findHits(words: [String], cleaned: [String], options: [CaptureRepoOption]) -> [Hit] {
        var hits: [Hit] = []
        let ordered = options.sorted { squash($0.name).count > squash($1.name).count }
        for option in ordered {
            let target = squash(option.name)
            guard target.count >= 2 else { continue }
            for start in cleaned.indices {
                var joined = ""
                for end in start..<min(start + 3, cleaned.count) {
                    if end > start, endsSentence(words[end - 1]) { break }
                    joined += cleaned[end].replacingOccurrences(of: " ", with: "")
                    if joined == target {
                        hits.append(Hit(option: option, start: start, end: end + 1))
                        break
                    }
                    if joined.count > target.count { break }
                }
            }
        }
        return hits.sorted { $0.start < $1.start }
    }

    /// The index of the preposition that introduces the name ("en", "para", "app de"), when there is one.
    private static func cueStart(for hit: Hit, cleaned: [String]) -> Int? {
        guard hit.start > 0 else { return nil }
        let before = cleaned[hit.start - 1]
        if prepositions.contains(before) {
            // "en la app de InSync" / "in the app of InSync": step back over the article and the noun.
            var index = hit.start - 1
            while index > 0, linkWords.contains(cleaned[index - 1]) { index -= 1 }
            return index
        }
        if ["de", "of"].contains(before), hit.start >= 2,
            ["app", "aplicacion", "repo", "repositorio", "proyecto", "project"].contains(cleaned[hit.start - 2]) {
            var index = hit.start - 2
            while index > 0, linkWords.contains(cleaned[index - 1]) { index -= 1 }
            return index
        }
        return nil
    }

    private static func trailingFiller(_ cleaned: [String], after end: Int) -> Bool {
        cleaned[end...].allSatisfy { $0.isEmpty || ["por", "favor", "please"].contains($0) }
    }

    private static func endsSentence(_ word: String) -> Bool {
        guard let last = word.last else { return false }
        return ":,;.-–—".contains(last)
    }

    /// Trimmed of the separators the naming phrase leaves around the task, and with a capital letter at
    /// the start unless the first word already has its own capitals: "iCloud no sincroniza" is not
    /// "ICloud", and ".gitignore" keeps its dot.
    private static func tidy(_ words: ArraySlice<String>) -> String {
        var joined = words.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,:;-–—\n"))
        while joined.hasSuffix(".") { joined.removeLast() }
        while joined.hasPrefix(". ") { joined.removeFirst(2) }
        guard let first = joined.first else { return "" }
        let firstWord = joined.prefix { !$0.isWhitespace }
        if firstWord.dropFirst().contains(where: \.isUppercase) { return joined }
        return first.uppercased() + joined.dropFirst()
    }
}
