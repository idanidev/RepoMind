import XCTest

@testable import RepoMind

final class KeychainManagerTests: XCTestCase {

    // KeychainManager is an actor
    func testSaveAndRetrieveToken() async throws {
        let manager = KeychainManager.shared
        let testKey = "test-account-key"
        let testToken = "ghp_test123"

        // Ensure clean state
        try? await manager.deleteToken(for: testKey)

        // Save
        try await manager.saveToken(testToken, for: testKey)

        // Retrieve
        let retrieved = try await manager.retrieveToken(for: testKey)
        XCTAssertEqual(retrieved, testToken)

        // Check existence
        let exists = await manager.hasToken(for: testKey)
        XCTAssertTrue(exists)

        // Cleanup
        try await manager.deleteToken(for: testKey)
    }

    func testDeleteToken() async throws {
        let manager = KeychainManager.shared
        let testKey = "test-delete-key"
        let testToken = "ghp_delete_me"

        // Save first
        try await manager.saveToken(testToken, for: testKey)

        // Confirm saved
        let saved = try await manager.retrieveToken(for: testKey)
        XCTAssertNotNil(saved)

        // Delete
        try await manager.deleteToken(for: testKey)

        // Confirm deleted
        let deleted = try await manager.retrieveToken(for: testKey)
        XCTAssertNil(deleted)
    }
}
