import XCTest
import GRDB
@testable import Echoic

final class TranscriptionStoreTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private var store: TranscriptionStore!

    override func setUp() async throws {
        dbQueue = try DatabaseQueue()
        try await dbQueue.write { db in
            try db.create(table: "transcriptSegment") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("meetingId", .text).notNull()
                t.column("startMs", .integer).notNull()
                t.column("endMs", .integer).notNull()
                t.column("speakerId", .text)
                t.column("text", .text).notNull()
                t.column("confidence", .double)
            }
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
}
