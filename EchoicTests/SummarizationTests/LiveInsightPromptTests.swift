import XCTest
@testable import Echoic

final class LiveInsightPromptTests: XCTestCase {
    private func segment(_ startSeconds: Int64, _ text: String, speaker: String? = nil) -> TranscriptSegment {
        TranscriptSegment(
            meetingId: "m1",
            startMs: startSeconds * 1000,
            endMs: startSeconds * 1000 + 5000,
            speakerId: speaker,
            text: text,
            confidence: nil
        )
    }

    func test_userMessage_firstRun_marksPreviousStateEmpty() {
        let message = LiveInsightPromptTemplate.userMessage(
            previous: nil,
            contextNote: "",
            earlierSegments: [],
            newSegments: [segment(0, "Let's talk about the launch date")]
        )

        XCTAssertTrue(message.contains("PREVIOUS STATE:\n(none yet)"))
        XCTAssertTrue(message.contains("[00:00] Others: Let's talk about the launch date"))
        XCTAssertFalse(message.contains("MEETING CONTEXT"))
    }

    func test_userMessage_includesPreviousStateContextAndEarlierLines() {
        let previous = LiveInsight(
            meetingId: "m1",
            createdAt: 0,
            coversUntilMs: 65_000,
            recap: "Debating the launch date.",
            concerns: ["QA capacity is unclear"],
            questions: ["Who owns the rollout?"]
        )

        let message = LiveInsightPromptTemplate.userMessage(
            previous: previous,
            contextNote: "Q3 launch planning",
            earlierSegments: [segment(60, "QA is stretched")],
            newSegments: [segment(120, "I can take the rollout", speaker: TranscriptSegment.localSpeakerId)]
        )

        XCTAssertTrue(message.contains("MEETING CONTEXT:\nQ3 launch planning"))
        XCTAssertTrue(message.contains("Recap: Debating the launch date."))
        XCTAssertTrue(message.contains("- QA capacity is unclear"))
        XCTAssertTrue(message.contains("- Who owns the rollout?"))
        XCTAssertTrue(message.contains("EARLIER CONTEXT"))
        XCTAssertTrue(message.contains("[01:00] Others: QA is stretched"))
        XCTAssertTrue(message.contains("NEW TRANSCRIPT"))
        XCTAssertTrue(message.contains("[02:00] You: I can take the rollout"))
    }

    func test_parseResponse_fullUpdate_decodes() throws {
        let text = """
        {"has_update": true, "recap": "Team picked May 3.", "concerns": ["No QA owner"], "questions": ["Is May 3 firm?"]}
        """

        let response = try AnthropicClient.decodeJSON(LiveInsightResponse.self, from: text)

        XCTAssertTrue(response.hasUpdate)
        XCTAssertEqual(response.recap, "Team picked May 3.")
        XCTAssertEqual(response.concerns, ["No QA owner"])
        XCTAssertEqual(response.questions, ["Is May 3 firm?"])
    }

    func test_parseResponse_fencedNoUpdate_decodesWithMissingFields() throws {
        let text = """
        ```json
        {"has_update": false}
        ```
        """

        let response = try AnthropicClient.decodeJSON(LiveInsightResponse.self, from: text)

        XCTAssertFalse(response.hasUpdate)
        XCTAssertNil(response.recap)
        XCTAssertNil(response.concerns)
    }

    func test_extractText_thinkingBlockFirst_returnsTextBlock() throws {
        let body = """
        {"content": [
          {"type": "thinking", "thinking": "", "signature": "abc"},
          {"type": "text", "text": "{\\"has_update\\": false}"}
        ], "stop_reason": "end_turn"}
        """.data(using: .utf8)!

        let text = try AnthropicClient.extractText(body)

        XCTAssertEqual(text, "{\"has_update\": false}")
    }

    func test_extractText_noTextBlock_throwsParseError() {
        let body = """
        {"content": [{"type": "thinking", "thinking": ""}], "stop_reason": "max_tokens"}
        """.data(using: .utf8)!

        XCTAssertThrowsError(try AnthropicClient.extractText(body))
    }

    func test_supportsServerSideFallback_opus55Yes_opus46No() {
        XCTAssertTrue(AnthropicClient.supportsServerSideFallback(model: "claude-opus-5-5"))
        XCTAssertFalse(AnthropicClient.supportsServerSideFallback(model: "claude-opus-4-6"))
        XCTAssertEqual(AnthropicClient.defaultLiveInsightsModel, "auto:opus")
    }
}
