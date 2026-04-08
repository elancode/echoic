import XCTest
import GRDB
@testable import Echoic

final class SpeakerMergeTests: XCTestCase {
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
                t.column("meetingId", .text).notNull().references("meeting", onDelete: .cascade)
                t.column("startMs", .integer).notNull()
                t.column("endMs", .integer).notNull()
                t.column("speakerId", .text)
                t.column("text", .text).notNull()
                t.column("confidence", .double)
            }
            try db.execute(sql: """
                CREATE VIRTUAL TABLE transcriptFts USING fts5(text, content='transcriptSegment', content_rowid='id', tokenize='porter')
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
                t.column("meetingId", .text).primaryKey().references("meeting", onDelete: .cascade)
                t.column("rawJson", .text).notNull()
                t.column("executiveSummary", .text)
                t.column("title", .text)
                t.column("createdAt", .integer).notNull()
            }
            try db.create(table: "meetingSpeaker") { t in
                t.column("meetingId", .text).notNull().references("meeting", onDelete: .cascade)
                t.column("speakerId", .text).notNull()
                t.column("label", .text).notNull()
                t.primaryKey(["meetingId", "speakerId"])
            }
        }
        try migrator.migrate(dbQueue)
    }

    func testMergeAssignsSpeakers() throws {
        let meetingId = "01HTEST_MERGE_001"

        // Insert meeting and segments
        try dbQueue.write { db in
            try Meeting(id: meetingId, title: "Merge Test", startedAt: 0, status: .ready).insert(db)
            var s1 = TranscriptSegment(meetingId: meetingId, startMs: 0, endMs: 5000, text: "Hello everyone", confidence: 0.9)
            try s1.insert(db)
            var s2 = TranscriptSegment(meetingId: meetingId, startMs: 5000, endMs: 10000, text: "Thanks for joining", confidence: 0.85)
            try s2.insert(db)
            var s3 = TranscriptSegment(meetingId: meetingId, startMs: 10000, endMs: 15000, text: "Let us begin", confidence: 0.9)
            try s3.insert(db)
        }

        // Speaker diarization results
        let speakerSegments = [
            DiarizationService.DiarizationSegment(startMs: 0, endMs: 6000, speakerId: "speaker_1"),
            DiarizationService.DiarizationSegment(startMs: 6000, endMs: 15000, speakerId: "speaker_2")
        ]

        try SpeakerMerge.merge(meetingId: meetingId, speakerSegments: speakerSegments, databaseWriter: dbQueue)

        // Verify speakers assigned
        let segments = try dbQueue.read { db in
            try TranscriptSegment
                .filter(TranscriptSegment.Columns.meetingId == meetingId)
                .order(TranscriptSegment.Columns.startMs)
                .fetchAll(db)
        }

        XCTAssertEqual(segments[0].speakerId, "speaker_1")
        XCTAssertEqual(segments[1].speakerId, "speaker_2")
        XCTAssertEqual(segments[2].speakerId, "speaker_2")

        // Verify meetingSpeaker entries created
        let speakers = try dbQueue.read { db in
            try MeetingSpeaker.fetchAll(db)
        }
        XCTAssertEqual(speakers.count, 2)
    }
}
