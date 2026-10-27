import XCTest

@testable import RepoMind

@MainActor
final class HomeTasksTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_043_200)

    private func row(
        _ title: String, repo: String, daysAgo: Double, state: HomeTaskState, unpublished: Bool = false
    ) -> HomeTaskRow {
        HomeTaskRow(
            id: UUID(), title: title, repoName: repo, repoCardID: "card-" + repo, columnName: nil,
            createdAt: now.addingTimeInterval(-daysAgo * 24 * 60 * 60), issueNumber: nil,
            needsIssueSync: unpublished, state: state)
    }

    private var rows: [HomeTaskRow] {
        [
            row("fix login", repo: "InSync", daysAgo: 1, state: .pending),
            row("export csv", repo: "Clarity", daysAgo: 2, state: .pending),
            row("dark mode", repo: "InSync", daysAgo: 10, state: .pending, unpublished: true),
            row("old done", repo: "InSync", daysAgo: 30, state: .done),
            row("widget", repo: "FOCVS", daysAgo: 3, state: .idea),
        ]
    }

    func testPendingGroupsByRepoWithTheBusiestFirst() {
        let groups = HomeTaskRow.groups(rows, filter: .pending, query: "", now: now)
        XCTAssertEqual(groups.map(\.repoName), ["InSync", "Clarity"])
        XCTAssertEqual(groups[0].rows.map(\.title), ["fix login", "dark mode"], "newest first inside a repo")
    }

    func testRecentCoversAWeekWhateverTheState() {
        let groups = HomeTaskRow.groups(rows, filter: .recent, query: "", now: now)
        XCTAssertEqual(groups.flatMap { $0.rows.map(\.title) }.sorted(), ["export csv", "fix login", "widget"])
    }

    func testDoneAndIdeasFilter() {
        XCTAssertEqual(HomeTaskRow.groups(rows, filter: .done, query: "", now: now).flatMap(\.rows).count, 1)
        XCTAssertEqual(HomeTaskRow.groups(rows, filter: .ideas, query: "", now: now).first?.repoName, "FOCVS")
    }

    func testSearchMatchesTitleOrRepo() {
        XCTAssertEqual(
            HomeTaskRow.groups(rows, filter: .pending, query: "CSV", now: now).flatMap(\.rows).map(\.title),
            ["export csv"])
        XCTAssertEqual(HomeTaskRow.groups(rows, filter: .pending, query: " insync ", now: now).count, 1)
        XCTAssertTrue(HomeTaskRow.groups(rows, filter: .pending, query: "nothing", now: now).isEmpty)
    }
}
