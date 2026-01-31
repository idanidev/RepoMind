import XCTest

@testable import RepoMind

final class GitHubServiceTests: XCTestCase {

    // GitHubService is an actor, so we test it within async context
    func testValidateToken_MockPro_ReturnsProUser() async throws {
        let service = GitHubService.shared
        let user = try await service.validateToken("mock-pro")

        XCTAssertEqual(user.login, "ProDev")
        XCTAssertEqual(user.name, "Pro Developer")
    }

    func testValidateToken_MockFree_ReturnsFreeUser() async throws {
        let service = GitHubService.shared
        let user = try await service.validateToken("mock-free")

        XCTAssertEqual(user.login, "FreeDev")
        XCTAssertEqual(user.name, "Free Developer")
    }

    func testFetchRepos_MockPro_Returns10Repos() async throws {
        let service = GitHubService.shared
        let repos = try await service.fetchRepos(token: "mock-pro")

        XCTAssertEqual(repos.count, 10)
        XCTAssertEqual(repos.first?.name, "Project Alpha 1")
    }

    func testFetchRepos_MockFree_Returns4Repos() async throws {
        let service = GitHubService.shared
        let repos = try await service.fetchRepos(token: "mock-free")

        XCTAssertEqual(repos.count, 4)
    }

    func testFetchStarredRepoIDs_Mock_ReturnsHardcodedIDs() async throws {
        let service = GitHubService.shared
        let ids = try await service.fetchStarredRepoIDs(token: "mock-pro")

        XCTAssertTrue(ids.contains(101))
        XCTAssertTrue(ids.contains(103))
        XCTAssertEqual(ids.count, 2)
    }
}
