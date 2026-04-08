import XCTest
import GRDB
@testable import Echoic

final class DatabaseManagerTests: XCTestCase {
    private var dbQueue: DatabaseQueue!

    override func setUp() async throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(configuration: config)

        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "meeting") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("startedAt", .integer).notNull()
                t.column("endedAt", .integer)
                t.column("durationMs", .integer)
                t.column("audioPath", .text)
                t.column("status", .text).notNull().defaults(to: "recording")
            }

            try db.create(table: "transcriptSegment") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("meetingId", .text)
                    .notNull()
                    .references("meeting", onDelete: .cascade)
                t.column("startMs", .integer).notNull()
                t.column("endMs", .integer).notNull()
                t.column("speakerId", .text)
                t.column("text", .text).notNull()
                t.column("confidence", .double)
            }

            try db.execute(sql: """
                CREATE VIRTUAL TABLE transcriptFts USING fts5(
                    text,
                    content='transcriptSegment',
                    content_rowid='id',
                    tokenize='porter'
                )
                """)

            try db.execute(sql: """
                CREATE TRIGGER transcriptSegment_ai AFTER INSERT ON transcriptSegment BEGIN
                    INSERT INTO transcriptFts(rowid, text) VALUES (new.id, new.text);
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER transcriptSegment_ad AFTER DELETE ON transcriptSegment BEGIN
                    INSERT INTO transcriptFts(transcriptFts, rowid, text) VALUES('delete', old.id, old.text);
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER transcriptSegment_au AFTER UPDATE ON transcriptSegment BEGIN
                    INSERT INTO transcriptFts(transcriptFts, rowid, text) VALUES('delete', old.id, old.text);
                    INSERT INTO transcriptFts(rowid, text) VALUES (new.id, new.text);
                END
                """)

            try db.create(table: "summary") { t in
                t.column("meetingId", .text).primaryKey()
                    .references("meeting", onDelete: .cascade)
                t.column("rawJson", .text).notNull()
                t.column("executiveSummary", .text)
                t.column("title", .text)
                t.column("createdAt", .integer).notNull()
            }

            try db.create(table: "meetingSpeaker") { t in
                t.column("meetingId", .text)
                    .notNull()
                    .references("meeting", onDelete: .cascade)
                t.column("speakerId", .text).notNull()
                t.column("label", .text).notNull()
                t.primaryKey(["meetingId", "speakerId"])
            }
        }
        try migrator.migrate(dbQueue)
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
