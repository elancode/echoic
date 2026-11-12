import XCTest
import GRDB
@testable import Echoic

final class TranscriptionStoreTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private var store: TranscriptionStore!

    override func setUp() async throws {
        dbQueue = try DatabaseQueue()
        try DatabaseManager.migrate(dbQueue)
        try await dbQueue.write { db in
            try Meeting(id: "m1", title: "Store Test", startedAt: 0, status: .recording).insert(db)
        }
        store = TranscriptionStore(databaseWriter: dbQueue)
    }

    override func tearDown() async throws {
        store = nil
        dbQueue = nil
    }

    func test_insert_newSegment_returnsStoredSegmentWithId() throws {
        let segment = TranscriptSegment(meetingId: "m1", startMs: 0, endMs: 5000, text: "Let's review the quarterly roadmap", confidence: 0.9)

        let stored = try store.insert(segment)

        XCTAssertNotNil(stored?.id)
        XCTAssertEqual(stored?.text, "Let's review the quarterly roadmap")
    }

    func test_insert_duplicateSegment_returnsNilAndDoesNotStore() throws {
        let first = TranscriptSegment(meetingId: "m1", startMs: 0, endMs: 5000, text: "Let's review the quarterly roadmap", confidence: 0.9)
        let duplicate = TranscriptSegment(meetingId: "m1", startMs: 100, endMs: 5100, text: "Let's review the quarterly roadmap", confidence: 0.85)

        try store.insert(first)
        let result = try store.insert(duplicate)

        XCTAssertNil(result)
        XCTAssertEqual(try store.segments(for: "m1").count, 1)
    }

    func test_insert_micSegmentEchoingSystemAudio_returnsNil() throws {
        let remote = TranscriptSegment(meetingId: "m1", startMs: 0, endMs: 5000, text: "The launch moved to the second week of March", confidence: 0.9)
        let echo = TranscriptSegment(meetingId: "m1", startMs: 2500, endMs: 5200, speakerId: TranscriptSegment.localSpeakerId,
                                     text: "moved to the second week of March", confidence: 0.8)

        try store.insert(remote)
        let result = try store.insert(echo)

        XCTAssertNil(result)
        XCTAssertEqual(try store.segments(for: "m1").count, 1)
    }

    func test_insert_micSegmentWithOwnSpeech_isStoredWithLocalSpeaker() throws {
        let remote = TranscriptSegment(meetingId: "m1", startMs: 0, endMs: 5000, text: "The launch moved to the second week of March", confidence: 0.9)
        let reply = TranscriptSegment(meetingId: "m1", startMs: 5200, endMs: 8000, speakerId: TranscriptSegment.localSpeakerId,
                                      text: "That works, I'll update the plan", confidence: 0.9)

        try store.insert(remote)
        let stored = try store.insert(reply)

        XCTAssertEqual(stored?.speakerId, TranscriptSegment.localSpeakerId)
        XCTAssertEqual(try store.segments(for: "m1").count, 2)
    }
}
