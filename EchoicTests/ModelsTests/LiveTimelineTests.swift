import XCTest
@testable import Echoic

final class LiveTimelineTests: XCTestCase {
    private func segment(_ startMs: Int64, _ endMs: Int64, _ speakerId: String?, _ text: String) -> TranscriptSegment {
        TranscriptSegment(meetingId: "m", startMs: startMs, endMs: endMs, speakerId: speakerId, text: text, confidence: 1)
    }

    // MARK: - Turns

    func test_turns_unidentifiedRemoteSpeech_isLabelledOthers() {
        let turns = LiveTimeline.turns(from: [segment(0, 2_000, nil, "Hi.")])

        XCTAssertEqual(turns.first?.label, "Others")
    }

    func test_turns_speakerChange_startsNewTurn() {
        let turns = LiveTimeline.turns(from: [
            segment(0, 2_000, nil, "Shall we start?"),
            segment(2_100, 4_000, "you", "Yes."),
            segment(4_100, 6_000, nil, "Great."),
        ])

        XCTAssertEqual(turns.map(\.label), ["Others", "You", "Others"])
        XCTAssertEqual(turns.map(\.startMs), [0, 2_100, 4_100])
    }

    func test_turns_shortGapsSameSpeaker_mergeIntoOneParagraph() {
        let turns = LiveTimeline.turns(from: [
            segment(0, 2_000, nil, "This made"),
            segment(2_500, 4_000, nil, "sense."),
        ])

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.paragraphs, ["This made sense."])
    }

    func test_turns_pauseOfTwoSecondsOrMore_startsNewParagraph() {
        let turns = LiveTimeline.turns(from: [
            segment(0, 2_000, nil, "First point."),
            segment(4_000, 6_000, nil, "Second point."),
        ])

        XCTAssertEqual(turns.first?.paragraphs, ["First point.", "Second point."])
    }

    func test_turns_paragraphOver45Seconds_breaks() {
        let segments = (0..<6).map { index in
            segment(Int64(index) * 10_000, Int64(index) * 10_000 + 9_500, nil, "Part \(index).")
        }

        let turns = LiveTimeline.turns(from: segments)

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.paragraphs.count, 2)
    }

    // MARK: - Timeline with bookmarks

    func test_items_bookmarkBetweenTurns_isPlacedByTime() {
        let turns = LiveTimeline.turns(from: [
            segment(0, 2_000, nil, "Before."),
            segment(10_000, 12_000, "you", "After."),
        ])

        let items = LiveTimeline.items(turns: turns, bookmarks: [5_000])

        XCTAssertEqual(items.map(\.kind), [.turn, .bookmark, .turn])
    }

    func test_items_bookmarkAfterLastTurn_isLast() {
        let turns = LiveTimeline.turns(from: [segment(0, 2_000, nil, "Only.")])

        let items = LiveTimeline.items(turns: turns, bookmarks: [9_000])

        XCTAssertEqual(items.map(\.kind), [.turn, .bookmark])
    }

    // MARK: - Following live

    func test_follow_userScrolledUp_pauses() {
        XCTAssertFalse(LiveTimeline.isFollowing(current: true, distanceFromBottom: 200, secondsSinceAutoScroll: 2))
    }

    func test_follow_contentGrewRightAfterAutoScroll_staysFollowing() {
        XCTAssertTrue(LiveTimeline.isFollowing(current: true, distanceFromBottom: 200, secondsSinceAutoScroll: 0.2))
    }

    func test_follow_userScrolledBackToBottom_resumes() {
        XCTAssertTrue(LiveTimeline.isFollowing(current: false, distanceFromBottom: 10, secondsSinceAutoScroll: 5))
    }
}
