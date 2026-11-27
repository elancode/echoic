import XCTest
@testable import Echoic

final class SummaryMarkdownTests: XCTestCase {
    private func decode(_ json: String) throws -> SummaryResponse {
        try JSONDecoder().decode(SummaryResponse.self, from: Data(json.utf8))
    }

    private let fullJSON = """
    {"title": "Pricing review", "meeting_type": "Strategy review", "executive_summary": "We agreed on two tiers.",
     "detailed_summary": "**Pricing**\\n\\nSarah argued for two tiers.",
     "decisions": [{"decision": "Ship two tiers", "speaker": "speaker_1", "timestamp_ms": 754000}],
     "action_items": [{"task": "Draft pricing page", "owner": "you", "due": "Friday"}],
     "open_questions": ["Do we need a team plan?"],
     "topics": [{"topic": "Tiers", "timestamp_ms": 0}, {"topic": "Launch date", "timestamp_ms": 3723000}]}
    """

    func test_decode_newFields_parsesOpenQuestionsAndTopics() throws {
        let response = try decode(fullJSON)

        XCTAssertEqual(response.openQuestions, ["Do we need a team plan?"])
        XCTAssertEqual(response.topics?.map(\.topic), ["Tiers", "Launch date"])
        XCTAssertEqual(response.topics?.last?.timestampMs, 3_723_000)
    }

    func test_decode_summaryWithoutNewFields_stillParses() throws {
        let response = try decode("""
        {"title": "T", "executive_summary": "S", "decisions": [], "action_items": []}
        """)

        XCTAssertNil(response.openQuestions)
        XCTAssertNil(response.topics)
    }

    func test_render_fullSummary_producesStructuredMarkdown() throws {
        let response = try decode(fullJSON)

        let markdown = SummaryMarkdown.render(
            response, title: "Pricing review", labels: ["speaker_1": "Sarah", "you": "You"]
        )

        XCTAssertTrue(markdown.hasPrefix("# Pricing review\n"))
        XCTAssertTrue(markdown.contains("We agreed on two tiers."))
        XCTAssertTrue(markdown.contains("## Decisions\n- Ship two tiers — Sarah [00:12:34]"))
        XCTAssertTrue(markdown.contains("## Action items\n- [ ] Draft pricing page — You, due Friday"))
        XCTAssertTrue(markdown.contains("## Open questions\n- Do we need a team plan?"))
        XCTAssertTrue(markdown.contains("## Topics\n- [00:00:00] Tiers\n- [01:02:03] Launch date"))
        XCTAssertTrue(markdown.contains("## Notes\n**Pricing**"))
    }

    func test_render_emptySections_omitsTheirHeadings() throws {
        let response = try decode("""
        {"title": "T", "executive_summary": "Short.", "decisions": [], "action_items": []}
        """)

        let markdown = SummaryMarkdown.render(response, title: "T", labels: [:])

        XCTAssertFalse(markdown.contains("## Decisions"))
        XCTAssertFalse(markdown.contains("## Action items"))
        XCTAssertFalse(markdown.contains("## Topics"))
    }

    func test_formatTimestamp_hoursMinutesSeconds_isBracketed() {
        XCTAssertEqual(Date.formatTimestamp(ms: 754_000), "[00:12:34]")
        XCTAssertEqual(Date.formatTimestamp(ms: 3_723_000), "[01:02:03]")
    }
}
