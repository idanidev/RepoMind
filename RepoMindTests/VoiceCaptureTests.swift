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
}
