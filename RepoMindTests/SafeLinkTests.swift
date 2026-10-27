import XCTest

@testable import RepoMind

final class SafeLinkTests: XCTestCase {
    func testAPlainHttpsAddressIsKept() {
        XCTAssertEqual(
            SafeLink.web("https://github.com/idanidev/InSync/issues/90")?.absoluteString,
            "https://github.com/idanidev/InSync/issues/90")
        XCTAssertNotNil(SafeLink.web("  https://github.com/x/y  "))
        XCTAssertNotNil(SafeLink.web("HTTPS://github.com/x/y"))
    }

    func testAnythingElseIsDropped() {
        for text in [
            "http://github.com/x/y",
            "javascript:alert(1)",
            "tel:+34600000000",
            "repomind://capture",
            "https://user:secret@example.com/x",
            "https://",
            "https:///path",
            "not a url",
            "",
        ] {
            XCTAssertNil(SafeLink.web(text), text)
        }
        XCTAssertNil(SafeLink.web(nil as String?))
    }

    func testTheGitHubTokenOnlyGoesToTheRawFileHostOverHttps() throws {
        func goes(_ text: String) throws -> Bool {
            GitHubService.sendsToken(to: try XCTUnwrap(URL(string: text), text))
        }
        XCTAssertTrue(try goes("https://raw.githubusercontent.com/a/b/main/x.png"))
        XCTAssertFalse(try goes("http://raw.githubusercontent.com/a/b/main/x.png"))
        XCTAssertFalse(try goes("https://raw.githubusercontent.com.evil.example/x"))
        XCTAssertFalse(try goes("https://example.com/x"))
        XCTAssertFalse(try goes("https://avatars.githubusercontent.com/u/1"))
    }

    func testANotificationNeverCarriesAUrlTheAppWouldNotOpen() {
        XCTAssertNil(NotificationTarget.parse(["target": "web", "url": "javascript:alert(1)"]))
        XCTAssertNil(NotificationTarget.parse(["target": "web", "url": "http://example.com"]))
        XCTAssertNil(NotificationTarget.parse(["target": "web"]))
        XCTAssertNotNil(NotificationTarget.parse(["target": "web", "url": "https://github.com/x/y/actions"]))
    }
}
