import XCTest

@testable import RepoMind

@MainActor
final class GlobalCaptureTests: XCTestCase {
    private let apps = [
        CaptureRepoOption(id: 1, name: "InSync", columns: ["To Do", "Doing", "Done"], ideaColumn: "Ideas"),
        CaptureRepoOption(id: 2, name: "RepoMind", columns: ["Backlog", "Doing"]),
        CaptureRepoOption(id: 3, name: "mi-api"),
        CaptureRepoOption(id: 4, name: "api-legacy"),
    ]

    // MARK: Folding and matching

    func testFoldIgnoresCaseAccentsAndPunctuation() {
        XCTAssertEqual(CaptureRepoResolver.fold("Añade, la  App!"), "anade la app")
        XCTAssertEqual(CaptureRepoResolver.squash("In-Sync"), "insync")
        XCTAssertEqual(CaptureRepoResolver.squash("repo mind"), "repomind")
    }

    func testMatchFindsTheAppHowevertheRecognizerSpelledIt() {
        XCTAssertEqual(CaptureRepoResolver.match("in sync", in: apps)?.id, 1)
        XCTAssertEqual(CaptureRepoResolver.match("Repo Mind", in: apps)?.id, 2)
        XCTAssertEqual(CaptureRepoResolver.match("mi api", in: apps)?.id, 3)
    }

    func testMatchRefusesAnAmbiguousOrUnknownName() {
        // "api" is inside two names: guessing would file the task under the wrong project.
        XCTAssertNil(CaptureRepoResolver.match("api", in: apps))
        XCTAssertNil(CaptureRepoResolver.match("nothing", in: apps))
        XCTAssertNil(CaptureRepoResolver.match("", in: apps))
    }

    // MARK: Detection

    func testAnAppNamedFirstIsTakenOutOfTheText() {
        let direct = CaptureRepoResolver.detect(in: "En InSync, arreglar el login", options: apps)
        XCTAssertEqual(direct?.option.id, 1)
        XCTAssertEqual(direct?.rest, "Arreglar el login")
        XCTAssertEqual(direct?.stripped, true)

        let command = CaptureRepoResolver.detect(in: "Añade una tarea en InSync arreglar el login", options: apps)
        XCTAssertEqual(command?.option.id, 1)
        XCTAssertEqual(command?.rest, "Arreglar el login")

        let colon = CaptureRepoResolver.detect(in: "InSync: arreglar el login", options: apps)
        XCTAssertEqual(colon?.rest, "Arreglar el login")

        let english = CaptureRepoResolver.detect(in: "In sync, fix the login crash", options: apps)
        XCTAssertEqual(english?.option.id, 1)
        XCTAssertEqual(english?.rest, "Fix the login crash")

        let longer = CaptureRepoResolver.detect(in: "para api legacy borrar el endpoint viejo", options: apps)
        XCTAssertEqual(longer?.option.id, 4)
        XCTAssertEqual(longer?.rest, "Borrar el endpoint viejo")
    }

    func testAnAppNamedLastIsTakenOutOfTheText() {
        let suffix = CaptureRepoResolver.detect(in: "Arreglar el login en InSync", options: apps)
        XCTAssertEqual(suffix?.option.id, 1)
        XCTAssertEqual(suffix?.rest, "Arreglar el login")

        let polite = CaptureRepoResolver.detect(
            in: "Arreglar la app de pagos en la app de InSync por favor", options: apps)
        XCTAssertEqual(polite?.option.id, 1)
        XCTAssertEqual(polite?.rest, "Arreglar la app de pagos")
    }

    func testAnAppMentionedInTheMiddleKeepsTheWholeText() {
        let text = "Arreglar el botón del login en InSync para que no se cierre"
        let found = CaptureRepoResolver.detect(in: text, options: apps)
        XCTAssertEqual(found?.option.id, 1)
        XCTAssertEqual(found?.rest, text)
        XCTAssertEqual(found?.stripped, false)

        let subject = CaptureRepoResolver.detect(in: "El widget de RepoMind no carga", options: apps)
        XCTAssertEqual(subject?.option.id, 2)
        XCTAssertEqual(subject?.stripped, false)
    }

    func testTwoAppsOrNoneIsNoAnswer() {
        XCTAssertNil(CaptureRepoResolver.detect(in: "Compara InSync con RepoMind", options: apps))
        XCTAssertNil(CaptureRepoResolver.detect(in: "arreglar el login", options: apps))
        XCTAssertNil(CaptureRepoResolver.detect(in: "", options: apps))
    }

    // MARK: Drafts

    func testFallbackFilesTheDictationUnderTheAppItNames() {
        let named = GlobalCaptureRouting.fallbackDraft(transcript: "En InSync, arreglar el login", options: apps)
        XCTAssertEqual(named.repoID, 1)
        XCTAssertEqual(named.title, "Arreglar el login")

        let unnamed = GlobalCaptureRouting.fallbackDraft(transcript: "arreglar el login", options: apps)
        XCTAssertNil(unnamed.repoID)
        XCTAssertEqual(unnamed.title, "arreglar el login")
    }

    func testFallbackUsesTheRecognizersHintOrTheOnlyApp() {
        // "…, añadir a InSync" at the end reaches the view model as a column name.
        let hinted = GlobalCaptureRouting.fallbackDraft(transcript: "arreglar el login", options: apps, hint: "in sync")
        XCTAssertEqual(hinted.repoID, 1)

        let alone = GlobalCaptureRouting.fallbackDraft(transcript: "arreglar el login", options: [apps[1]])
        XCTAssertEqual(alone.repoID, 2)
    }

    func testTheModelsAppAndColumnAreCheckedAgainstTheRealOnes() {
        let draft = GlobalCaptureRouting.draft(
            title: "Arreglar el login", details: "", kind: "bug", repo: "in sync", column: "doing",
            transcript: "en in sync arreglar el login", options: apps)
        XCTAssertEqual(draft.repoID, 1)
        XCTAssertEqual(draft.kind, .bug)
        XCTAssertEqual(draft.columnName, "Doing")

        // A column of another app is not a column of this one.
        let foreign = GlobalCaptureRouting.draft(
            title: "x", details: "", kind: "feature", repo: "InSync", column: "Backlog",
            transcript: "x", options: apps)
        XCTAssertEqual(foreign.repoID, 1)
        XCTAssertNil(foreign.columnName)
    }

    func testTheModelNamingNoAppFallsBackToTheTextThenToTheOnlyApp() {
        let fromText = GlobalCaptureRouting.draft(
            title: "Widget", details: "", kind: "idea", repo: "", column: "",
            transcript: "El widget de RepoMind no carga", options: apps)
        XCTAssertEqual(fromText.repoID, 2)

        let none = GlobalCaptureRouting.draft(
            title: "Widget", details: "", kind: "idea", repo: "", column: "",
            transcript: "un widget", options: apps)
        XCTAssertNil(none.repoID)

        let idea = GlobalCaptureRouting.draft(
            title: "Widget", details: "", kind: "idea", repo: "InSync", column: "",
            transcript: "x", options: apps)
        XCTAssertEqual(idea.columnName, "Ideas")
    }

    func testABoardsDraftHasNoApp() {
        XCTAssertNil(CaptureDraft(title: "x").repoID)
        XCTAssertNil(CaptureDraft.fallback(transcript: "x", columnName: nil).repoID)
    }

    // MARK: Vocabulary and router

    func testVocabularyPutsTheAppsFirstAndStaysShort() {
        let terms = VoiceVocabulary.terms(repoNames: ["InSync", "RepoMind"], columns: ["Doing", "insync"])
        XCTAssertEqual(Array(terms.prefix(2)), ["InSync", "RepoMind"])
        XCTAssertEqual(terms.filter { $0.lowercased() == "insync" }.count, 1)
        XCTAssertLessThanOrEqual(terms.count, 120)
    }

    func testARequestIsConsumedOnce() {
        // Its own router: the shared one is listened to by the app the tests run in.
        let router = GlobalCaptureRouter()
        XCTAssertFalse(router.consumePending())
        router.request()
        XCTAssertTrue(router.consumePending())
        XCTAssertFalse(router.consumePending())
    }
}
