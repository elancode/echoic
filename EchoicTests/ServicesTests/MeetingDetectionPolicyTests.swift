import XCTest
@testable import Echoic

final class MeetingDetectionPolicyTests: XCTestCase {
    private var policy: MeetingDetectionPolicy!
    private let start = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        policy = MeetingDetectionPolicy(minimumActiveDuration: 5)
    }

    override func tearDown() {
        policy = nil
    }

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    func test_update_micActiveShorterThanThreshold_returnsNone() {
        XCTAssertEqual(policy.update(micInUse: true, canRecord: true, now: at(0)), .none)
        XCTAssertEqual(policy.update(micInUse: true, canRecord: true, now: at(4)), .none)
    }

    func test_update_micActiveForThreshold_returnsPrompt() {
        _ = policy.update(micInUse: true, canRecord: true, now: at(0))

        XCTAssertEqual(policy.update(micInUse: true, canRecord: true, now: at(5)), .prompt)
        XCTAssertTrue(policy.isPromptVisible)
    }

    func test_update_afterPromptInSameMicSession_doesNotPromptAgain() {
        _ = policy.update(micInUse: true, canRecord: true, now: at(0))
        _ = policy.update(micInUse: true, canRecord: true, now: at(5))
        policy.promptHandled()

        XCTAssertEqual(policy.update(micInUse: true, canRecord: true, now: at(60)), .none)
    }

    func test_update_micReleasedWhilePromptVisible_returnsDismissPrompt() {
        _ = policy.update(micInUse: true, canRecord: true, now: at(0))
        _ = policy.update(micInUse: true, canRecord: true, now: at(5))

        XCTAssertEqual(policy.update(micInUse: false, canRecord: true, now: at(10)), .dismissPrompt)
        XCTAssertFalse(policy.isPromptVisible)
    }

    func test_update_micReleasedAfterPromptHandled_returnsNone() {
        _ = policy.update(micInUse: true, canRecord: true, now: at(0))
        _ = policy.update(micInUse: true, canRecord: true, now: at(5))
        policy.promptHandled()

        XCTAssertEqual(policy.update(micInUse: false, canRecord: true, now: at(10)), .none)
    }

    func test_update_newMicSessionAfterRelease_promptsAgain() {
        _ = policy.update(micInUse: true, canRecord: true, now: at(0))
        _ = policy.update(micInUse: true, canRecord: true, now: at(5))
        policy.promptHandled()
        _ = policy.update(micInUse: false, canRecord: true, now: at(10))

        _ = policy.update(micInUse: true, canRecord: true, now: at(20))
        XCTAssertEqual(policy.update(micInUse: true, canRecord: true, now: at(25)), .prompt)
    }

    func test_update_briefMicBlips_doNotAccumulateTowardThreshold() {
        _ = policy.update(micInUse: true, canRecord: true, now: at(0))
        _ = policy.update(micInUse: true, canRecord: true, now: at(3))
        _ = policy.update(micInUse: false, canRecord: true, now: at(4))
        _ = policy.update(micInUse: true, canRecord: true, now: at(5))

        XCTAssertEqual(policy.update(micInUse: true, canRecord: true, now: at(8)), .none)
    }

    func test_update_cannotRecord_neverPrompts() {
        _ = policy.update(micInUse: true, canRecord: false, now: at(0))

        XCTAssertEqual(policy.update(micInUse: true, canRecord: false, now: at(30)), .none)
    }

    func test_update_recordingStartsWhilePromptVisible_returnsDismissPrompt() {
        _ = policy.update(micInUse: true, canRecord: true, now: at(0))
        _ = policy.update(micInUse: true, canRecord: true, now: at(5))

        XCTAssertEqual(policy.update(micInUse: true, canRecord: false, now: at(6)), .dismissPrompt)
    }

    func test_update_recordingStoppedMidCall_doesNotPromptAgain() {
        _ = policy.update(micInUse: true, canRecord: false, now: at(0))
        _ = policy.update(micInUse: true, canRecord: false, now: at(30))

        XCTAssertEqual(policy.update(micInUse: true, canRecord: true, now: at(60)), .none)
    }
}
