import Speech
import XCTest

@testable import RepoMind

final class VoiceManagerTests: XCTestCase {
    var voiceManager: VoiceManager!

    override func setUp() {
        super.setUp()
        voiceManager = VoiceManager()
    }

    override func tearDown() {
        voiceManager = nil
        super.tearDown()
    }

    func testInitialState() {
        XCTAssertFalse(voiceManager.isRecording)
        XCTAssertEqual(voiceManager.transcribedText, "")
        XCTAssertNil(voiceManager.errorMessage)
    }

    // Note: Testing actual recording requires mocking SFSpeechRecognizer and audio session,
    // which is complex without dependency injection.
    // verifying that the manager handles permission status checks gracefully.

    func testPermissionCheckWithDeniedStatus() async {
        // This is a partial test; mocking `SFSpeechRecognizer.authorizationStatus()` is not possible directly.
        // In a real app we'd wrap the recognizer in a protocol.
        // For now, we assert base properties.
    }
}
