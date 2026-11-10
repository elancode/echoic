import XCTest
import GRDB
@testable import Echoic

final class DatabaseManagerTests: XCTestCase {
    private var dbQueue: DatabaseQueue!

    override func setUp() async throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(configuration: config)

        try DatabaseManager.migrate(dbQueue)
    }

    override func tearDown() {
        dbQueue = nil
    }

    func testInsertMeeting() throws {
        let meeting = Meeting(
            id: "01HTEST000000000000000001",
            title: "Test Meeting",
            startedAt: 1700000000000,
            status: .recording
        )

        try dbQueue.write { db in
            try meeting.insert(db)
        }

        let fetched = try dbQueue.read { db in
            try Meeting.fetchOne(db, key: "01HTEST000000000000000001")
        }

        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Test Meeting")
        XCTAssertEqual(fetched?.status, .recording)
    }

    func testInsertTranscriptSegment() throws {
        let meeting = Meeting(
            id: "01HTEST000000000000000002",
            title: "Transcript Test",
            startedAt: 1700000000000,
            status: .recording
        )

        var segment = TranscriptSegment(
            meetingId: "01HTEST000000000000000002",
            startMs: 0,
            endMs: 10000,
            text: "Hello world this is a test transcript",
            confidence: 0.95
        )

        try dbQueue.write { db in
            try meeting.insert(db)
            try segment.insert(db)
        }

        XCTAssertNotNil(segment.id)
    }

    func testFullTextSearch() throws {
        let meeting = Meeting(
            id: "01HTEST000000000000000003",
            title: "FTS Test",
            startedAt: 1700000000000,
            status: .ready
        )

        var segment1 = TranscriptSegment(
            meetingId: "01HTEST000000000000000003",
            startMs: 0,
            endMs: 10000,
            text: "We need to migrate the database before Friday",
            confidence: 0.9
        )

        var segment2 = TranscriptSegment(
            meetingId: "01HTEST000000000000000003",
            startMs: 10000,
            endMs: 20000,
            text: "The API endpoint is already deployed",
            confidence: 0.85
        )

        try dbQueue.write { db in
            try meeting.insert(db)
            try segment1.insert(db)
            try segment2.insert(db)
        }

        // Search for "migrate" — should match via Porter stemmer ("migration" would also match)
        let results = try dbQueue.read { db -> [TranscriptSegment] in
            let sql = """
                SELECT transcriptSegment.* FROM transcriptSegment
                JOIN transcriptFts ON transcriptFts.rowid = transcriptSegment.id
                WHERE transcriptFts MATCH ?
                """
            return try TranscriptSegment.fetchAll(db, sql: sql, arguments: ["migrate"])
        }

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].text.contains("migrate"))
    }

    func testCascadeDelete() throws {
        let meeting = Meeting(
            id: "01HTEST000000000000000004",
            title: "Cascade Test",
            startedAt: 1700000000000,
            status: .ready
        )

        var segment = TranscriptSegment(
            meetingId: "01HTEST000000000000000004",
            startMs: 0,
            endMs: 5000,
            text: "This should be deleted with the meeting",
            confidence: 0.9
        )

        let summary = Summary(
            meetingId: "01HTEST000000000000000004",
            rawJson: "{}",
            executiveSummary: "Test",
            title: "Test",
            createdAt: 1700000000000
        )

        try dbQueue.write { db in
            try meeting.insert(db)
            try segment.insert(db)
            try summary.insert(db)
        }

        // Delete the meeting
        try dbQueue.write { db in
            _ = try Meeting.deleteOne(db, key: "01HTEST000000000000000004")
        }

        // Verify cascade
        let segments = try dbQueue.read { db in
            try TranscriptSegment.filter(TranscriptSegment.Columns.meetingId == "01HTEST000000000000000004").fetchAll(db)
        }
        let summaries = try dbQueue.read { db in
            try Summary.fetchOne(db, key: "01HTEST000000000000000004")
        }

        XCTAssertTrue(segments.isEmpty)
        XCTAssertNil(summaries)
    }
}
