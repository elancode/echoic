import Foundation
import GRDB

/// A single segment of transcribed text within a meeting.
struct TranscriptSegment: Codable, Identifiable {
    var id: Int64?
    var meetingId: String
    var startMs: Int64
    var endMs: Int64
    var speakerId: String?
    var text: String
    var confidence: Double?
}

// MARK: - GRDB Record Conformance

extension TranscriptSegment: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "transcriptSegment"

    enum Columns: String, ColumnExpression {
        case id, meetingId, startMs, endMs, speakerId, text, confidence
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
