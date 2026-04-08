import XCTest
@testable import Echoic

final class SummarizationTests: XCTestCase {
    func testPromptFormatting() {
        let segments = [
            TranscriptSegment(meetingId: "m1", startMs: 0, endMs: 5000, speakerId: "speaker_1", text: "Hello everyone", confidence: 0.9),
            TranscriptSegment(meetingId: "m1", startMs: 5000, endMs: 10000, speakerId: "speaker_2", text: "Thanks for joining", confidence: 0.85),
            TranscriptSegment(meetingId: "m1", startMs: 3_661_000, endMs: 3_666_000, speakerId: "speaker_1", text: "Let's wrap up", confidence: 0.9)
        ]

        let formatted = SummaryPromptTemplate.formatTranscript(segments)

        XCTAssertTrue(formatted.contains("[00:00] speaker_1: Hello everyone"))
        XCTAssertTrue(formatted.contains("[00:05] speaker_2: Thanks for joining"))
        XCTAssertTrue(formatted.contains("[01:01:01] speaker_1: Let's wrap up"))
    }

    func testSummaryResponseParsing() throws {
        let json = """
        {
          "title": "Q2 Planning",
          "meeting_type": "product review",
          "participants": "Speaker 1 (PM), Speaker 2 (Eng)",
          "duration_tone": "30-min planning session, focused tone",
          "executive_summary": "Team aligned on priorities.",
          "detailed_summary": "The team discussed the Q2 roadmap.\\n\\nThey decided to ship v2 first.",
          "decisions": [{"decision": "Ship v2 first", "speaker": "Speaker 1", "timestamp_ms": 5000}],
          "action_items": [{"task": "Draft plan", "owner": "Speaker 2", "due": "Friday"}],
          "notable_quotes": [{"quote": "Ship it or kill it", "speaker": "Speaker 1", "context": "On v2 timeline"}]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SummaryResponse.self, from: json)

        XCTAssertEqual(response.title, "Q2 Planning")
        XCTAssertEqual(response.meetingType, "product review")
        XCTAssertEqual(response.detailedSummary?.contains("roadmap"), true)
        XCTAssertEqual(response.decisions.count, 1)
        XCTAssertEqual(response.actionItems.count, 1)
        XCTAssertEqual(response.actionItems[0].owner, "Speaker 2")
        XCTAssertEqual(response.notableQuotes?.count, 1)
    }

    func testChunkingThreshold() {
        // Under 3 hours — no chunking
        XCTAssertFalse(MeetingChunker.needsChunking(durationMs: 2 * 60 * 60 * 1000))

        // Over 3 hours — needs chunking
        XCTAssertTrue(MeetingChunker.needsChunking(durationMs: 4 * 60 * 60 * 1000))
    }

    func testChunkSplitting() {
        // Create 4 hours of segments (1 per minute)
        let segments = (0..<240).map { i in
            TranscriptSegment(
                meetingId: "m1",
                startMs: Int64(i) * 60_000,
                endMs: Int64(i + 1) * 60_000,
                text: "Segment \(i)",
                confidence: 0.9
            )
        }

        let chunks = MeetingChunker.chunk(segments)

        // 240 minutes / 90 minutes = 3 chunks (roughly)
        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        XCTAssertLessThanOrEqual(chunks.count, 4)

        // All segments accounted for
        let totalSegments = chunks.reduce(0) { $0 + $1.count }
        XCTAssertEqual(totalSegments, 240)
    }

    func testRetryConfigDefaults() {
        let config = RetryHandler.Config()
        XCTAssertEqual(config.maxAttempts, 3)
        XCTAssertEqual(config.initialDelay, 1.0)
        XCTAssertEqual(config.maxDelay, 300.0)
    }
}
