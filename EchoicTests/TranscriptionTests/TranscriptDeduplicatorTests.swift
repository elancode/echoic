import XCTest
@testable import Echoic

final class TranscriptDeduplicatorTests: XCTestCase {
    func testExactDuplicate() {
        let existing = [
            TranscriptSegment(meetingId: "m1", startMs: 0, endMs: 5000, text: "Hello world how are you", confidence: 0.9)
        ]

        let candidate = TranscriptSegment(meetingId: "m1", startMs: 100, endMs: 5100, text: "Hello world how are you", confidence: 0.85)

        XCTAssertTrue(TranscriptDeduplicator.isDuplicate(candidate, of: existing))
    }

    func testSimilarOverlapping() {
        let existing = [
            TranscriptSegment(meetingId: "m1", startMs: 0, endMs: 5000, text: "We need to migrate the database before Friday", confidence: 0.9)
        ]

        let candidate = TranscriptSegment(meetingId: "m1", startMs: 200, endMs: 5200, text: "We need to migrate the database before Friday deadline", confidence: 0.88)

        XCTAssertTrue(TranscriptDeduplicator.isDuplicate(candidate, of: existing))
    }

    func testDifferentSegment() {
        let existing = [
            TranscriptSegment(meetingId: "m1", startMs: 0, endMs: 5000, text: "Hello world how are you", confidence: 0.9)
        ]

        let candidate = TranscriptSegment(meetingId: "m1", startMs: 6000, endMs: 11000, text: "The API is already deployed", confidence: 0.85)

        XCTAssertFalse(TranscriptDeduplicator.isDuplicate(candidate, of: existing))
    }

    func testTextSimilarity() {
        XCTAssertEqual(TranscriptDeduplicator.textSimilarity("hello world", "hello world"), 1.0)
        // "hello world" ∩ "goodbye world" = {"world"}, union = {"hello","world","goodbye"} = 1/3
        XCTAssertEqual(TranscriptDeduplicator.textSimilarity("hello world", "goodbye world"), 1.0/3.0, accuracy: 0.01)
        XCTAssertEqual(TranscriptDeduplicator.textSimilarity("hello", "goodbye"), 0.0)
    }

    func testMergePreferHigherConfidence() {
        var segments = [
            TranscriptSegment(meetingId: "m1", startMs: 0, endMs: 5000, text: "Hello world how are you doing today", confidence: 0.8)
        ]

        let better = TranscriptSegment(meetingId: "m1", startMs: 100, endMs: 5100, text: "Hello world how are you doing today friend", confidence: 0.95)

        TranscriptDeduplicator.merge(better, into: &segments)

        // Should replace with higher confidence version (similarity > 0.7)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].confidence, 0.95)
    }

    func testMergeAppendsNewSegment() {
        var segments = [
            TranscriptSegment(meetingId: "m1", startMs: 0, endMs: 5000, text: "Hello world", confidence: 0.8)
        ]

        let different = TranscriptSegment(meetingId: "m1", startMs: 10000, endMs: 15000, text: "Something else entirely", confidence: 0.9)

        TranscriptDeduplicator.merge(different, into: &segments)

        XCTAssertEqual(segments.count, 2)
    }
}
