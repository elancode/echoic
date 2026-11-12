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

// MARK: - Speakers

extension TranscriptSegment {
    /// Speaker ID for segments transcribed from the local user's microphone.
    static let localSpeakerId = "you"

    /// Whether this segment came from the local user's microphone.
    var isLocalSpeaker: Bool {
        speakerId == Self.localSpeakerId
    }

    /// Label for display and summaries ("You" for the local user).
    var speakerDisplayName: String {
        isLocalSpeaker ? "You" : (speakerId ?? "Unknown")
    }
}

extension Array where Element == TranscriptSegment {
    /// Inserts a segment keeping the array ordered by start time. Segments from
    /// separate audio streams (system + mic) arrive out of order.
    mutating func insertByStartTime(_ segment: TranscriptSegment) {
        let index = lastIndex { $0.startMs <= segment.startMs }.map { $0 + 1 } ?? 0
        insert(segment, at: index)
    }
}
