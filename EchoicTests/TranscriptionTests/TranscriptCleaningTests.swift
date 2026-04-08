import XCTest
@testable import Echoic

final class TranscriptCleaningTests: XCTestCase {
    func testRemovesXMLTags() {
        let input = "<start of transcript> Hello world <end>"
        let cleaned = TranscriptionService.cleanTranscriptText(input)
        XCTAssertEqual(cleaned, "Hello world")
    }

    func testRemovesSilenceTags() {
        let input = "Some text <silence> more text"
        let cleaned = TranscriptionService.cleanTranscriptText(input)
        XCTAssertEqual(cleaned, "Some text  more text")
    }

    func testRemovesHallucinatedPhrases() {
        let input = "The meeting is over. Thank you for watching."
        let cleaned = TranscriptionService.cleanTranscriptText(input)
        XCTAssertEqual(cleaned, "The meeting is over.")
    }

    func testReturnsEmptyForTagOnlyText() {
        let input = "<start of transcript>"
        let cleaned = TranscriptionService.cleanTranscriptText(input)
        XCTAssertTrue(cleaned.isEmpty)
    }

    func testPreservesNormalText() {
        let input = "We need to ship the feature by Friday"
        let cleaned = TranscriptionService.cleanTranscriptText(input)
        XCTAssertEqual(cleaned, input)
    }

    func testTrimsWhitespace() {
        let input = "  hello world  "
        let cleaned = TranscriptionService.cleanTranscriptText(input)
        XCTAssertEqual(cleaned, "hello world")
    }
}
