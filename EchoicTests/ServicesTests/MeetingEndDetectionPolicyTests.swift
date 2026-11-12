import XCTest
@testable import Echoic

final class MeetingEndDetectionPolicyTests: XCTestCase {
    private var policy: MeetingEndDetectionPolicy!
    private let start = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        policy = MeetingEndDetectionPolicy(minimumInactiveDuration: 10)
    }

    override func tearDown() {
        policy = nil
    }

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    /// Recording with another app on the mic, which releases it at `releaseAt`.
    private func recordCallThatEnds(releaseAt: TimeInterval) {
        _ = policy.update(micInUse: true, isRecording: true, now: at(0))
        _ = policy.update(micInUse: false, isRecording: true, now: at(releaseAt))
    }

    func test_update_micReleasedShorterThanThreshold_returnsNone() {
        recordCallThatEnds(releaseAt: 60)

        XCTAssertEqual(policy.update(micInUse: false, isRecording: true, now: at(69)), .none)
    }

    func test_update_micReleasedForThreshold_returnsPrompt() {
        recordCallThatEnds(releaseAt: 60)

        XCTAssertEqual(policy.update(micInUse: false, isRecording: true, now: at(70)), .prompt)
        XCTAssertTrue(policy.isPromptVisible)
    }

    func test_update_micNeverUsedDuringRecording_neverPrompts() {
        _ = policy.update(micInUse: false, isRecording: true, now: at(0))

        XCTAssertEqual(policy.update(micInUse: false, isRecording: true, now: at(120)), .none)
    }

    func test_update_micBriefDropDuringCall_doesNotPrompt() {
        recordCallThatEnds(releaseAt: 60)
        _ = policy.update(micInUse: true, isRecording: true, now: at(65))

        XCTAssertEqual(policy.update(micInUse: false, isRecording: true, now: at(72)), .none)
    }

    func test_update_micResumesWhilePromptVisible_returnsDismissPrompt() {
        recordCallThatEnds(releaseAt: 60)
        _ = policy.update(micInUse: false, isRecording: true, now: at(70))

        XCTAssertEqual(policy.update(micInUse: true, isRecording: true, now: at(75)), .dismissPrompt)
        XCTAssertFalse(policy.isPromptVisible)
    }

    func test_update_recordingStopsWhilePromptVisible_returnsDismissPrompt() {
        recordCallThatEnds(releaseAt: 60)
        _ = policy.update(micInUse: false, isRecording: true, now: at(70))

        XCTAssertEqual(policy.update(micInUse: false, isRecording: false, now: at(71)), .dismissPrompt)
    }

    func test_update_afterKeepRecording_doesNotPromptAgainUntilMicReused() {
        recordCallThatEnds(releaseAt: 60)
        _ = policy.update(micInUse: false, isRecording: true, now: at(70))
        policy.promptHandled()

        XCTAssertEqual(policy.update(micInUse: false, isRecording: true, now: at(200)), .none)
    }

    func test_update_micReusedAfterKeepRecording_promptsAgainWhenReleased() {
        recordCallThatEnds(releaseAt: 60)
        _ = policy.update(micInUse: false, isRecording: true, now: at(70))
        policy.promptHandled()

        _ = policy.update(micInUse: true, isRecording: true, now: at(100))
        _ = policy.update(micInUse: false, isRecording: true, now: at(150))
        XCTAssertEqual(policy.update(micInUse: false, isRecording: true, now: at(160)), .prompt)
    }

    func test_update_newRecordingWithoutMic_doesNotInheritPreviousCall() {
        _ = policy.update(micInUse: true, isRecording: true, now: at(0))
        _ = policy.update(micInUse: true, isRecording: false, now: at(30))

        _ = policy.update(micInUse: false, isRecording: true, now: at(40))
        XCTAssertEqual(policy.update(micInUse: false, isRecording: true, now: at(100)), .none)
    }
}
