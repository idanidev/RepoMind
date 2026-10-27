import XCTest

@testable import RepoMind

final class TaskIssueSyncTests: XCTestCase {
    // MARK: Marker

    func testTheMarkerOfAPublishedIssueGivesBackItsTask() {
        let id = UUID()
        let body = "Fix the login\n\n<!-- repomind-task:\(id.uuidString) -->"

        XCTAssertEqual(TaskIssueSyncService.taskMarker(in: body), id)
        XCTAssertEqual(TaskIssueSyncService.taskMarker(in: body.lowercased()), id)
    }

    func testAnIssueWithoutOurMarkerHasNoTask() {
        XCTAssertNil(TaskIssueSyncService.taskMarker(in: "A bug somebody opened by hand"))
        XCTAssertNil(TaskIssueSyncService.taskMarker(in: "<!-- repomind-task:not-a-uuid -->"))
        XCTAssertNil(TaskIssueSyncService.taskMarker(in: ""))
        XCTAssertNil(TaskIssueSyncService.taskMarker(in: nil))
    }

    // MARK: Rate limits

    private func response(_ status: Int, headers: [String: String] = [:]) throws -> HTTPURLResponse {
        let url = try XCTUnwrap(URL(string: "https://api.github.com/repos/idanidev/InSync/issues"))
        return try XCTUnwrap(
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
    }

    func testARateLimitIsToldApartFromALackOfPermission() throws {
        // GitHub answers a rate limit with 403: reading it as "no permission" switched sync off for the repo.
        XCTAssertTrue(TaskIssueSyncService.isRateLimited(
            try response(403, headers: ["Retry-After": "60"]), data: Data()))
        XCTAssertTrue(TaskIssueSyncService.isRateLimited(
            try response(403, headers: ["x-ratelimit-remaining": "0"]), data: Data()))
        XCTAssertTrue(TaskIssueSyncService.isRateLimited(
            try response(403), data: Data("You have exceeded a secondary rate limit.".utf8)))
        XCTAssertTrue(TaskIssueSyncService.isRateLimited(
            try response(429, headers: ["Retry-After": "5"]), data: Data()))
    }

    func testARealLackOfPermissionIsNotARateLimit() throws {
        XCTAssertFalse(TaskIssueSyncService.isRateLimited(
            try response(403, headers: ["x-ratelimit-remaining": "4999"]),
            data: Data("Resource not accessible by personal access token".utf8)))
        XCTAssertFalse(TaskIssueSyncService.isRateLimited(try response(403), data: Data()))
    }
}
