import XCTest
@testable import Echoic

final class CrossTalkFilterTests: XCTestCase {
    private func system(_ startMs: Int64, _ endMs: Int64, _ text: String) -> TranscriptSegment {
        TranscriptSegment(meetingId: "m1", startMs: startMs, endMs: endMs, text: text, confidence: 0.9)
    }

    private func mic(_ startMs: Int64, _ endMs: Int64, _ text: String) -> TranscriptSegment {
        TranscriptSegment(meetingId: "m1", startMs: startMs, endMs: endMs,
                          speakerId: TranscriptSegment.localSpeakerId, text: text, confidence: 0.9)
    }

    func test_isBleed_micTextMatchesOverlappingSystemSegment_returnsTrue() {
        let recent = [system(10_000, 14_000, "We should ship the new onboarding flow on Monday")]

        XCTAssertTrue(CrossTalkFilter.isBleed(mic(10_400, 14_200, "should ship the new onboarding flow on Monday"), against: recent))
    }

    func test_isBleed_punctuationAndCaseDiffer_returnsTrue() {
        let recent = [system(0, 3_000, "Okay, sounds good. Let's do it!")]

        XCTAssertTrue(CrossTalkFilter.isBleed(mic(200, 3_100, "okay sounds good lets do it"), against: recent))
    }

    func test_isBleed_micTextSpansTwoSystemSegments_returnsTrue() {
        let recent = [
            system(0, 4_000, "The budget review is on Thursday"),
            system(4_000, 8_000, "and finance needs the numbers by Wednesday"),
        ]

        XCTAssertTrue(CrossTalkFilter.isBleed(mic(2_000, 7_000, "review is on Thursday and finance needs the numbers"), against: recent))
    }

    func test_isBleed_micTextDiffers_returnsFalse() {
        let recent = [system(10_000, 14_000, "We should ship the new onboarding flow on Monday")]

        XCTAssertFalse(CrossTalkFilter.isBleed(mic(10_500, 13_000, "I think Tuesday works better for my team"), against: recent))
    }

    func test_isBleed_matchingTextFarApartInTime_returnsFalse() {
        let recent = [system(0, 4_000, "Can everyone hear me okay")]

        XCTAssertFalse(CrossTalkFilter.isBleed(mic(60_000, 63_000, "Can everyone hear me okay"), against: recent))
    }

    func test_isBleed_onlyOtherMicSegmentsMatch_returnsFalse() {
        let recent = [mic(0, 4_000, "Let me share my screen")]

        XCTAssertFalse(CrossTalkFilter.isBleed(mic(500, 4_200, "Let me share my screen"), against: recent))
    }
}
