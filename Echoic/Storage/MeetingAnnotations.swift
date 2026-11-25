import Foundation
import GRDB

/// A moment the user marked while recording, as an offset from the meeting start.
struct Bookmark: Codable, Equatable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var meetingId: String
    var offsetMs: Int64
    var createdAt: Int64

    static let databaseTableName = "bookmark"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// User annotations on a meeting: bookmarks and completed action items.
enum MeetingAnnotations {
    static func addBookmark(meetingId: String, offsetMs: Int64, db: Database) throws {
        var bookmark = Bookmark(
            id: nil, meetingId: meetingId, offsetMs: max(0, offsetMs),
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        try bookmark.insert(db)
    }

    static func bookmarks(meetingId: String, db: Database) throws -> [Bookmark] {
        try Bookmark
            .filter(Column("meetingId") == meetingId)
            .order(Column("offsetMs"))
            .fetchAll(db)
    }

    static func setActionItem(_ task: String, done: Bool, meetingId: String, db: Database) throws {
        if done {
            try db.execute(
                sql: "INSERT OR REPLACE INTO actionItemStatus (meetingId, task, completedAt) VALUES (?, ?, ?)",
                arguments: [meetingId, task, Int64(Date().timeIntervalSince1970 * 1000)]
            )
        } else {
            try db.execute(
                sql: "DELETE FROM actionItemStatus WHERE meetingId = ? AND task = ?",
                arguments: [meetingId, task]
            )
        }
    }

    static func completedActionItems(meetingId: String, db: Database) throws -> Set<String> {
        Set(try String.fetchAll(db, sql: "SELECT task FROM actionItemStatus WHERE meetingId = ?", arguments: [meetingId]))
    }
}
