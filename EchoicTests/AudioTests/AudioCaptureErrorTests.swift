import XCTest
@testable import Echoic

final class AudioCaptureErrorTests: XCTestCase {
    func testPermissionNotGrantedDescription() {
        let error = AudioCaptureError.permissionNotGranted
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Screen Recording"))
        XCTAssertTrue(error.errorDescription!.contains("System Settings"))
    }

    func testAllErrorCasesHaveDescriptions() {
        let cases: [AudioCaptureError] = [
            .noDisplayFound,
            .captureAlreadyRunning,
            .permissionDenied,
            .permissionNotGranted
        ]
        for error in cases {
            XCTAssertNotNil(error.errorDescription, "\(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "\(error) description should not be empty")
        }
    }

    func testErrorConformsToLocalizedError() {
        let error: Error = AudioCaptureError.permissionNotGranted
        XCTAssertFalse(error.localizedDescription.contains("permissionNotGranted"),
                       "localizedDescription should use errorDescription, not the case name")
    }

    func testPermissionNotGrantedMentionsToggle() {
        let error = AudioCaptureError.permissionNotGranted
        XCTAssertTrue(error.errorDescription!.contains("toggle"),
                      "Error should tell user to toggle permission off and back on")
    }

    // MARK: - MeetingState

    func testMeetingStateRecordingState() {
        XCTAssertEqual(MeetingState.idle.recordingState, .idle)
        XCTAssertEqual(MeetingState.recording.recordingState, .recording)
        XCTAssertEqual(MeetingState.processing.recordingState, .processing)
        XCTAssertEqual(MeetingState.error("test").recordingState, .idle)
    }

    func testMeetingStateErrorText() {
        XCTAssertNil(MeetingState.idle.errorText)
        XCTAssertNil(MeetingState.recording.errorText)
        XCTAssertEqual(MeetingState.error("fail").errorText, "fail")
    }
}
