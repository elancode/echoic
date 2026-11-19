import XCTest
@testable import Echoic

final class LiveInsightPolicyTests: XCTestCase {
    private let policy = LiveInsightPolicy()

    private func shouldRun(
        newSpeechMs: Int64,
        secondsSinceLastSegment: TimeInterval = 0,
        secondsSinceLastRun: TimeInterval? = nil,
        inFlight: Bool = false,
        manual: Bool = false
    ) -> Bool {
        policy.shouldRun(
            newSpeechMs: newSpeechMs,
            secondsSinceLastSegment: secondsSinceLastSegment,
            secondsSinceLastRun: secondsSinceLastRun,
            inFlight: inFlight,
            manual: manual
        )
    }

    func test_shouldRun_belowSpeechThreshold_returnsFalse() {
        XCTAssertFalse(shouldRun(newSpeechMs: 60_000))
    }

    func test_shouldRun_speechThresholdReached_returnsTrue() {
        XCTAssertTrue(shouldRun(newSpeechMs: 90_000))
    }

    func test_shouldRun_pauseAfterEnoughSpeech_returnsTrue() {
        XCTAssertTrue(shouldRun(newSpeechMs: 45_000, secondsSinceLastSegment: 8))
    }

    func test_shouldRun_pauseAfterTooLittleSpeech_returnsFalse() {
        XCTAssertFalse(shouldRun(newSpeechMs: 20_000, secondsSinceLastSegment: 30))
    }

    func test_shouldRun_withinCooldown_returnsFalse() {
        XCTAssertFalse(shouldRun(newSpeechMs: 200_000, secondsSinceLastRun: 60))
    }

    func test_shouldRun_afterCooldown_returnsTrue() {
        XCTAssertTrue(shouldRun(newSpeechMs: 200_000, secondsSinceLastRun: 91))
    }

    func test_shouldRun_requestInFlight_returnsFalse() {
        XCTAssertFalse(shouldRun(newSpeechMs: 200_000, inFlight: true))
        XCTAssertFalse(shouldRun(newSpeechMs: 200_000, inFlight: true, manual: true))
    }

    func test_shouldRun_manualWithNewSpeech_ignoresThresholdAndCooldown() {
        XCTAssertTrue(shouldRun(newSpeechMs: 1_000, secondsSinceLastRun: 5, manual: true))
    }

    func test_shouldRun_manualWithoutNewSpeech_returnsFalse() {
        XCTAssertFalse(shouldRun(newSpeechMs: 0, manual: true))
    }
}
