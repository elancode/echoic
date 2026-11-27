import GRDB
import XCTest
@testable import Echoic

final class MeetingAnnotationsTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private let meetingId = "01HTEST_ANNOTATIONS"

    override func setUpWithError() throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(configuration: config)
        try DatabaseManager.migrate(dbQueue)
        try dbQueue.write { db in
            try Meeting(id: meetingId, title: "Test", startedAt: 0, status: .recording).insert(db)
        }
    }

    override func tearDown() {
        dbQueue = nil
    }

    func test_addBookmark_twoOffsets_fetchesInTimeOrder() throws {
        try dbQueue.write { db in
            try MeetingAnnotations.addBookmark(meetingId: meetingId, offsetMs: 90_000, db: db)
            try MeetingAnnotations.addBookmark(meetingId: meetingId, offsetMs: 30_000, db: db)
        }

        let bookmarks = try dbQueue.read { try MeetingAnnotations.bookmarks(meetingId: meetingId, db: $0) }
        XCTAssertEqual(bookmarks.map(\.offsetMs), [30_000, 90_000])
    }

    func test_setActionItemDone_toggledTwice_reflectsLatestState() throws {
        try dbQueue.write { db in
            try MeetingAnnotations.setActionItem("Draft pricing page", done: true, meetingId: meetingId, db: db)
        }
        var done = try dbQueue.read { try MeetingAnnotations.completedActionItems(meetingId: meetingId, db: $0) }
        XCTAssertEqual(done, ["Draft pricing page"])

        try dbQueue.write { db in
            try MeetingAnnotations.setActionItem("Draft pricing page", done: false, meetingId: meetingId, db: db)
        }
        done = try dbQueue.read { try MeetingAnnotations.completedActionItems(meetingId: meetingId, db: $0) }
        XCTAssertTrue(done.isEmpty)
    }

    func test_deleteMeeting_withAnnotations_cascades() throws {
        try dbQueue.write { db in
            try MeetingAnnotations.addBookmark(meetingId: meetingId, offsetMs: 1_000, db: db)
            try MeetingAnnotations.setActionItem("Task", done: true, meetingId: meetingId, db: db)
            try db.execute(sql: "DELETE FROM meeting WHERE id = ?", arguments: [meetingId])
        }

        let counts = try dbQueue.read { db in
            (try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM bookmark") ?? -1,
             try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM actionItemStatus") ?? -1)
        }
        XCTAssertEqual(counts.0, 0)
        XCTAssertEqual(counts.1, 0)
    }
}
