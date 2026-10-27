import XCTest

@testable import RepoMind

@MainActor
final class VoiceCaptureTests: XCTestCase {
    private let columns = ["To Do", "Doing", "Ideas", "Done"]

    func testContentPutsTheTitleFirstAndTheDetailsAfterABlankLine() {
        XCTAssertEqual(CaptureDraft(title: "Fix login").content, "Fix login")
        XCTAssertEqual(CaptureDraft(title: "Fix login", details: " steps \n").content, "Fix login\n\nsteps")
    }

    func testFallbackKeepsTheDictationAndTheRoutedColumn() {
        let draft = CaptureDraft.fallback(transcript: "la pantalla salta", columnName: "Doing")
        XCTAssertEqual(draft.title, "la pantalla salta")
        XCTAssertEqual(draft.columnName, "Doing")
        XCTAssertEqual(draft.kind, .feature)
    }

    func testComposedDraftMatchesColumnsAndKinds() {
        let exact = CaptureDraft(
            title: " Arreglar el login ", details: "", kind: "Bug", column: "doing",
            columns: columns, ideaColumn: "Ideas")
        XCTAssertEqual(exact.title, "Arreglar el login")
        XCTAssertEqual(exact.kind, .bug)
        XCTAssertEqual(exact.columnName, "Doing")

        let contained = CaptureDraft(
            title: "x", details: "", kind: "chore", column: "to do column", columns: columns, ideaColumn: nil)
        XCTAssertEqual(contained.columnName, "To Do")

        let unknown = CaptureDraft(
            title: "x", details: "", kind: "something", column: "nowhere", columns: columns, ideaColumn: nil)
        XCTAssertEqual(unknown.kind, .feature)
        XCTAssertNil(unknown.columnName)
    }

    func testAnIdeaGoesToTheIdeasColumnUnlessOneWasNamed() {
        let idea = CaptureDraft(
            title: "x", details: "", kind: "idea", column: "", columns: columns, ideaColumn: "Ideas")
        XCTAssertEqual(idea.columnName, "Ideas")

        let named = CaptureDraft(
            title: "x", details: "", kind: "idea", column: "Doing", columns: columns, ideaColumn: "Ideas")
        XCTAssertEqual(named.columnName, "Doing")

        let noIdeas = CaptureDraft(
            title: "x", details: "", kind: "idea", column: "", columns: columns, ideaColumn: nil)
        XCTAssertNil(noIdeas.columnName)
    }

    func testContentTrimsTheTitleToo() {
        XCTAssertEqual(CaptureDraft(title: "  Fix login \n").content, "Fix login")
    }

    // MARK: "añadir a …" only when it names something

    private let names = ["To Do", "Doing", "En progreso", "Revisión", "Hecho"]

    func testACommandAtTheEndNamingAColumnRoutesAndLeavesTheText() throws {
        let done = try XCTUnwrap(VoiceManager.routing(in: "Arreglar el login, añadir a Hecho", names: names))
        XCTAssertEqual(done.text, "Arreglar el login")
        XCTAssertEqual(done.name, "Hecho")

        // Case, accents and the punctuation the recognizer adds do not matter; the board's own spelling comes back.
        let review = try XCTUnwrap(VoiceManager.routing(in: "revisar los permisos mover a revision.", names: names))
        XCTAssertEqual(review.text, "revisar los permisos")
        XCTAssertEqual(review.name, "Revisión")

        let several = try XCTUnwrap(VoiceManager.routing(in: "Probar el pago move to en PROGRESO", names: names))
        XCTAssertEqual(several.name, "En progreso")
    }

    func testASentenceThatOnlyContainsTheCommandIsLeftAlone() {
        // The old pattern cut these at "de", and the recording stopped mid-sentence.
        XCTAssertNil(VoiceManager.routing(in: "Arreglar el botón de añadir a favoritos", names: names))
        XCTAssertNil(VoiceManager.routing(in: "We should move to async await in the networking layer", names: names))
        XCTAssertNil(VoiceManager.routing(in: "poner un botón add to cart que no funciona", names: names))
        XCTAssertNil(VoiceManager.routing(in: "mover a hecho por favor revisar", names: names))
    }

    func testTheCommandNeedsSomethingBeforeItAndANameAfterIt() {
        XCTAssertNil(VoiceManager.routing(in: "añadir a Hecho", names: names), "nothing to add")
        XCTAssertNil(VoiceManager.routing(in: "Arreglar el login, añadir a", names: names))
        XCTAssertNil(VoiceManager.routing(in: "Arreglar el login, añadir a Hecho", names: []))
    }

    func testTheLastCommandThatNamesSomethingWins() throws {
        let found = try XCTUnwrap(
            VoiceManager.routing(in: "arreglar add to cart, move to Doing", names: names))
        XCTAssertEqual(found.text, "arreglar add to cart")
        XCTAssertEqual(found.name, "Doing")
    }

    // MARK: Adding a dictation to a capture

    private func rawDraft(_ text: String) -> CaptureDraft { CaptureDraft(title: text) }

    func testTheFirstDictationOpensACapture() {
        let addition = VoiceCapture.adding("arreglar el login", to: nil, isComposing: true, draft: rawDraft)
        XCTAssertEqual(addition.capture.transcript, "arreglar el login")
        XCTAssertEqual(addition.capture.drafts.map(\.title), ["arreglar el login"])
        XCTAssertEqual(addition.target, addition.capture.drafts)
        XCTAssertTrue(addition.capture.isComposing)
        XCTAssertFalse(addition.capture.hasUserEdits)
    }

    func testKeepDictatingWithNothingEditedWorksOutEverythingAgain() {
        let first = VoiceCapture.adding("arreglar el login", to: nil, isComposing: false, draft: rawDraft).capture
        let second = VoiceCapture.adding("y también el botón", to: first, isComposing: false, draft: rawDraft)

        XCTAssertEqual(second.capture.id, first.id, "the sheet is presented by this identity")
        XCTAssertEqual(second.capture.revision, first.revision + 1)
        XCTAssertEqual(second.capture.transcript, "arreglar el login\ny también el botón")
        XCTAssertEqual(second.capture.drafts.count, 1)
        XCTAssertEqual(second.dictated, "arreglar el login\ny también el botón")
    }

    func testKeepDictatingAfterAnEditKeepsTheEditAndAddsACard() {
        var capture = VoiceCapture.adding("arreglar el login", to: nil, isComposing: false, draft: rawDraft).capture
        capture.drafts[0].title = "Arreglar el login de Apple"
        capture.drafts[0].kind = .bug
        XCTAssertTrue(capture.hasUserEdits)

        let added = VoiceCapture.adding("revisar el botón", to: capture, isComposing: false, draft: rawDraft)

        XCTAssertEqual(added.capture.drafts.map(\.title), ["Arreglar el login de Apple", "revisar el botón"])
        XCTAssertEqual(added.capture.drafts[0].kind, .bug)
        XCTAssertEqual(added.target.map(\.title), ["revisar el botón"], "only the new card may be reshaped")
        XCTAssertEqual(added.dictated, "revisar el botón")
        XCTAssertTrue(added.capture.hasUserEdits, "and it stays that way")
    }

    func testTheModelsAnswerReplacesOnlyWhatNobodyTouched() {
        var capture = VoiceCapture.adding("arreglar login", to: nil, isComposing: true, draft: rawDraft).capture
        let snapshot = capture.drafts
        let shaped = [CaptureDraft(title: "Arreglar el login", kind: .bug), CaptureDraft(title: "Otra cosa")]

        XCTAssertTrue(capture.applyComposed(shaped, replacing: snapshot))
        XCTAssertEqual(capture.drafts.map(\.title), ["Arreglar el login", "Otra cosa"])
        XCTAssertTrue(capture.composedByAI)
        XCTAssertFalse(capture.hasUserEdits)

        // The person changed the title while "Giving it shape…" was showing: their work wins.
        var edited = VoiceCapture.adding("arreglar login", to: nil, isComposing: true, draft: rawDraft).capture
        let before = edited.drafts
        edited.drafts[0].title = "Arreglar el login de Apple"
        XCTAssertFalse(edited.applyComposed(shaped, replacing: before))
        XCTAssertEqual(edited.drafts.map(\.title), ["Arreglar el login de Apple"])
        XCTAssertFalse(edited.composedByAI)

        // Or removed the card.
        var removed = VoiceCapture.adding("x", to: nil, isComposing: true, draft: rawDraft).capture
        let gone = removed.drafts
        removed.drafts.removeAll()
        XCTAssertFalse(removed.applyComposed(shaped, replacing: gone))
        XCTAssertTrue(removed.drafts.isEmpty)
    }

    func testAnEmptyAnswerFromTheModelChangesNothing() {
        var capture = VoiceCapture.adding("x", to: nil, isComposing: true, draft: rawDraft).capture
        let snapshot = capture.drafts
        XCTAssertFalse(capture.applyComposed([], replacing: snapshot))
        XCTAssertEqual(capture.drafts, snapshot)
    }
}
