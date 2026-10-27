import SwiftData
import XCTest

@testable import RepoMind

@MainActor
final class NotificationTargetTests: XCTestCase {
    private var container: ModelContainer?

    override func tearDown() {
        container = nil
    }

    // MARK: Round trip

    func testEveryTargetSurvivesTheNotificationsUserInfo() throws {
        let issue = UUID()
        let tasks = [UUID(), UUID()]
        let web = try XCTUnwrap(URL(string: "https://github.com/idanidev/InSync/actions"))
        let targets: [NotificationTarget] = [
            .feedback(issueID: issue),
            .tasks(repoID: 7, taskIDs: tasks),
            .board(repoID: 7),
            .stats(repoID: 7),
            .web(web),
        ]
        for target in targets {
            let userInfo = Dictionary(uniqueKeysWithValues: target.userInfo.map { (AnyHashable($0.key), $0.value) })
            XCTAssertEqual(NotificationTarget.parse(userInfo), target)
        }
    }

    func testOnlyAPageOnGitHubCanBeOpenedBeforeTheReposArrive() throws {
        let page = try XCTUnwrap(URL(string: "https://github.com/idanidev/InSync/actions"))
        XCTAssertFalse(NotificationTarget.web(page).needsRepos)
        XCTAssertTrue(NotificationTarget.board(repoID: 1).needsRepos)
        XCTAssertTrue(NotificationTarget.stats(repoID: 1).needsRepos)
        XCTAssertTrue(NotificationTarget.feedback(issueID: UUID()).needsRepos)
        XCTAssertTrue(NotificationTarget.tasks(repoID: 1, taskIDs: []).needsRepos)
    }

    func testTheFirstVersionsFeedbackNotificationStillOpensTheReport() {
        let id = UUID()
        let legacy: [AnyHashable: Any] = ["feedbackIssueID": id.uuidString, "htmlURL": "https://github.com/x/y/1"]
        XCTAssertEqual(NotificationTarget.parse(legacy), .feedback(issueID: id))
    }

    func testAnUnreadableUserInfoLeadsNowhere() {
        XCTAssertNil(NotificationTarget.parse([:]))
        XCTAssertNil(NotificationTarget.parse(["target": "feedback"]))
        XCTAssertNil(NotificationTarget.parse(["target": "feedback", "issueID": "not a uuid"]))
        XCTAssertNil(NotificationTarget.parse(["target": "tasks"]))
        XCTAssertNil(NotificationTarget.parse(["target": "something else", "repoID": 1]))
        XCTAssertNil(NotificationTarget.parse(["importedRepo": "InSync"]))
    }

    // MARK: Text

    func testAnIssueLineLeadsWithTheNumberOnOneLine() {
        let line = NotificationText.issueLine(number: 12, title: "The shifts\n  screen   crashes")
        XCTAssertEqual(line, "#12 The shifts screen crashes")
        XCTAssertEqual(NotificationText.issueLine(number: 0, title: "No number"), "No number")
    }

    func testALongIssueTitleIsClipped() {
        let line = NotificationText.issueLine(number: 3, title: String(repeating: "a", count: 300), limit: 20)
        XCTAssertEqual(line, "#3 " + String(repeating: "a", count: 19) + "…")
    }

    func testTheShortRepoNameIsTheLastComponent() {
        XCTAssertEqual(NotificationText.shortRepoName("idanidev/InSync"), "InSync")
        XCTAssertEqual(NotificationText.shortRepoName("InSync"), "InSync")
    }

    // MARK: Alerts lead somewhere useful

    func testEachAlertLeadsToTheScreenThatHasTheAnswer() throws {
        let base = "https://github.com/idanidev/InSync"
        func alert(_ kind: RepoAlertRules.Kind) -> RepoAlertRules.Alert {
            RepoAlertRules.Alert(kind: kind, repoID: 7, title: "t", body: "b")
        }
        XCTAssertEqual(
            RepoAlertRules.target(for: alert(.ci), htmlURL: base),
            .web(try XCTUnwrap(URL(string: base + "/actions"))))
        XCTAssertEqual(
            RepoAlertRules.target(for: alert(.releases), htmlURL: base + "/"),
            .web(try XCTUnwrap(URL(string: base + "/releases/latest"))))
        XCTAssertEqual(
            RepoAlertRules.target(for: alert(.security), htmlURL: base),
            .web(try XCTUnwrap(URL(string: base + "/security/dependabot"))))
        XCTAssertEqual(RepoAlertRules.target(for: alert(.crashes), htmlURL: base), .stats(repoID: 7))
        // A repo with no GitHub page still leads to its board.
        XCTAssertEqual(RepoAlertRules.target(for: alert(.ci), htmlURL: ""), .board(repoID: 7))
    }

    // MARK: Resolution against the store

    private struct Fixture {
        let repo: ProjectRepo
        let todo: KanbanColumn
        let first: TaskItem
        let second: TaskItem
        let report: FeedbackIssue
    }

    private func makeFixture() throws -> Fixture {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: ProjectRepo.self, TaskItem.self, KanbanColumn.self, GitHubAccount.self, FeedbackIssue.self,
            configurations: config)
        self.container = container
        let context = container.mainContext

        let repo = ProjectRepo(repoID: 7, name: "InSync", htmlURL: "https://github.com/idanidev/InSync")
        context.insert(repo)
        let todo = KanbanColumn(name: "To Do", orderIndex: 0, project: repo)
        context.insert(todo)
        repo.columns = [todo]
        let first = TaskItem(content: "one", column: todo, project: repo)
        let second = TaskItem(content: "two", column: todo, project: repo)
        context.insert(first)
        context.insert(second)
        let report = FeedbackIssue(issueNumber: 4, repoFullName: "idanidev/InSync", title: "Crash")
        context.insert(report)
        try context.save()
        return Fixture(repo: repo, todo: todo, first: first, second: second, report: report)
    }

    func testAReportOpensItsRepoOnTheReport() throws {
        let fixture = try makeFixture()
        let destination = NotificationTarget.feedback(issueID: fixture.report.id)
            .destination(repos: [fixture.repo], feedback: [fixture.report])
        guard case .board(let repo, let focus) = destination else { return XCTFail("expected a board") }
        XCTAssertEqual(repo.repoID, 7)
        XCTAssertEqual(focus, .feedback(fixture.report.id))
    }

    func testOneImportedTaskOpensOnTheTask() throws {
        let fixture = try makeFixture()
        let destination = NotificationTarget.tasks(repoID: 7, taskIDs: [fixture.first.id])
            .destination(repos: [fixture.repo], feedback: [])
        guard case .board(_, let focus) = destination else { return XCTFail("expected a board") }
        XCTAssertEqual(focus, .task(fixture.first.id))
    }

    func testSeveralImportedTasksOpenOnTheirColumn() throws {
        let fixture = try makeFixture()
        let destination = NotificationTarget.tasks(repoID: 7, taskIDs: [fixture.first.id, fixture.second.id])
            .destination(repos: [fixture.repo], feedback: [])
        guard case .board(_, let focus) = destination else { return XCTFail("expected a board") }
        XCTAssertEqual(focus, .column(fixture.todo.id))
    }

    func testWhatNoLongerExistsLeadsNowhere() throws {
        let fixture = try makeFixture()
        XCTAssertNil(NotificationTarget.feedback(issueID: UUID()).destination(repos: [fixture.repo], feedback: []))
        XCTAssertNil(NotificationTarget.board(repoID: 99).destination(repos: [fixture.repo], feedback: []))
        XCTAssertNil(NotificationTarget.stats(repoID: 99).destination(repos: [fixture.repo], feedback: []))
    }

    func testTheRouterKeepsATargetUntilItIsCleared() {
        let router = NotificationRouter.shared
        router.clear()
        XCTAssertNil(router.pending)
        router.open(.board(repoID: 7))
        XCTAssertEqual(router.pending, .board(repoID: 7))
        router.clear()
        XCTAssertNil(router.pending)
    }
}
