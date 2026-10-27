import SwiftData
import XCTest

@testable import RepoMind

@MainActor
final class IssueSyncSwitchTests: XCTestCase {
    private var container: ModelContainer?

    /// The container is dropped here, in a synchronous `tearDown`, as the other suites do.
    override func tearDown() {
        container = nil
    }

    private func memory() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: ProjectRepo.self, TaskItem.self, KanbanColumn.self, GitHubAccount.self, configurations: config)
        self.container = container
        return container.mainContext
    }

    func testSwitchingSyncOffClearsWhatWasWaitingToBePublished() throws {
        let context = try memory()
        let repo = ProjectRepo(repoID: 4_242, name: "Sync")
        repo.syncTasksToGitHub = true
        context.insert(repo)
        let waiting = TaskItem(content: "waiting", project: repo, needsIssueSync: true)
        waiting.lastSyncError = "offline"
        let published = TaskItem(content: "published", project: repo, issueNumber: 7)
        [waiting, published].forEach(context.insert)
        try context.save()

        repo.stopSyncingTasks()

        XCTAssertFalse(repo.syncTasksToGitHub)
        XCTAssertFalse(waiting.needsIssueSync, "with sync off nothing is waiting, and the badge never cleared")
        XCTAssertNil(waiting.lastSyncError)
        XCTAssertEqual(published.issueNumber, 7, "issues already on GitHub are left alone")
    }

    func testAnotherReposTasksAreNotTouched() throws {
        let context = try memory()
        let off = ProjectRepo(repoID: 1, name: "Off")
        let on = ProjectRepo(repoID: 2, name: "On")
        [off, on].forEach(context.insert)
        let kept = TaskItem(content: "still waiting", project: on, needsIssueSync: true)
        context.insert(kept)
        try context.save()

        off.stopSyncingTasks()

        XCTAssertTrue(kept.needsIssueSync)
    }
}
