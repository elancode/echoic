import XCTest
@testable import Echoic

final class TranscriptSegmentTests: XCTestCase {
    private func segment(_ startMs: Int64, _ text: String) -> TranscriptSegment {
        TranscriptSegment(meetingId: "m1", startMs: startMs, endMs: startMs + 1000, text: text, confidence: 0.9)
    }

    func test_insertByStartTime_inOrder_appends() {
        var segments = [segment(0, "a"), segment(1000, "b")]

        segments.insertByStartTime(segment(2000, "c"))

        XCTAssertEqual(segments.map(\.text), ["a", "b", "c"])
    }

    func test_insertByStartTime_earlierSegment_insertsBeforeLaterOnes() {
        var segments = [segment(0, "a"), segment(8000, "c")]

        segments.insertByStartTime(segment(3000, "b"))

        XCTAssertEqual(segments.map(\.text), ["a", "b", "c"])
    }

    func test_insertByStartTime_equalStartTime_insertsAfterExisting() {
        var segments = [segment(0, "a"), segment(5000, "b")]

        segments.insertByStartTime(segment(5000, "b2"))

        XCTAssertEqual(segments.map(\.text), ["a", "b", "b2"])
    }

    func test_isLocalSpeaker_youSpeakerId_returnsTrue() {
        var mine = segment(0, "hi")
        mine.speakerId = TranscriptSegment.localSpeakerId

        XCTAssertTrue(mine.isLocalSpeaker)
        XCTAssertFalse(segment(0, "hi").isLocalSpeaker)
    }
}
