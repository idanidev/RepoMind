import XCTest

@testable import RepoMind

final class TaskLabelsTests: XCTestCase {
    private let id = UUID()

    override func tearDown() {
        TaskLabelStore.remove(for: id)
    }

    func testGitHubLabelsFollowTheKindAndTheAgentFlag() {
        XCTAssertEqual(TaskLabels(kind: .bug, delegated: true).gitHubLabels, ["bug", "agent"])
        XCTAssertEqual(TaskLabels(kind: .feature).gitHubLabels, ["enhancement"])
        XCTAssertEqual(TaskLabels(kind: nil, delegated: true).gitHubLabels, ["agent"])
        XCTAssertTrue(TaskLabels().gitHubLabels.isEmpty)
    }

    func testStoreRoundTripsAndForgets() {
        XCTAssertNil(TaskLabelStore.labels(for: id))
        TaskLabelStore.set(TaskLabels(kind: .chore, delegated: true), for: id)
        XCTAssertEqual(TaskLabelStore.labels(for: id), TaskLabels(kind: .chore, delegated: true))
        TaskLabelStore.remove(for: id)
        XCTAssertNil(TaskLabelStore.labels(for: id))
    }
}
