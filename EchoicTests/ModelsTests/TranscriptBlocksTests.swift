import XCTest
@testable import Echoic

final class TranscriptBlocksTests: XCTestCase {
    private func segment(_ startMs: Int64, _ speakerId: String?, _ text: String) -> TranscriptSegment {
        TranscriptSegment(meetingId: "m", startMs: startMs, endMs: startMs + 1_000, speakerId: speakerId, text: text, confidence: 1)
    }

    func test_make_consecutiveSameSpeaker_mergesIntoOneBlock() {
        let blocks = TranscriptBlocks.make(
            from: [segment(0, "speaker_1", "Hi."), segment(1_000, "speaker_1", "Shall we start?"),
                   segment(2_000, "you", "Yes.")],
            labels: ["speaker_1": "Sarah"]
        )

        XCTAssertEqual(blocks.map(\.label), ["Sarah", "You"])
        XCTAssertEqual(blocks.first?.text, "Hi. Shall we start?")
        XCTAssertEqual(blocks.map(\.startMs), [0, 2_000])
    }

    func test_make_unlabelledSpeaker_usesDefaultLabel() {
        let blocks = TranscriptBlocks.make(from: [segment(0, "speaker_3", "Hello")], labels: [:])

        XCTAssertEqual(blocks.first?.label, "Speaker 3")
    }

    func test_blockId_timestampInsideBlock_returnsThatBlock() {
        let blocks = TranscriptBlocks.make(
            from: [segment(0, "a", "1"), segment(10_000, "b", "2"), segment(20_000, "a", "3")], labels: [:]
        )

        XCTAssertEqual(TranscriptBlocks.blockId(containing: 15_000, in: blocks), 10_000)
        XCTAssertEqual(TranscriptBlocks.blockId(containing: 0, in: blocks), 0)
        XCTAssertEqual(TranscriptBlocks.blockId(containing: 99_000, in: blocks), 20_000)
    }

    func test_blockId_noBlocks_returnsNil() {
        XCTAssertNil(TranscriptBlocks.blockId(containing: 1_000, in: []))
    }
}
