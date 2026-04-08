import Foundation
import GRDB

/// Represents a recorded meeting.
struct Meeting: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var startedAt: Int64
    var endedAt: Int64?
    var durationMs: Int64?
    var audioPath: String?
    var status: Status
    var processed: Bool = false

    enum Status: String, Codable, DatabaseValueConvertible {
        case recording
        case processing
        case ready
        case error
    }

    /// Creates a new meeting with a generated ULID.
    static func create(title: String? = nil) -> Meeting {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let defaultTitle = "Meeting on \(Date().meetingDisplayString)"
        return Meeting(
            id: ULID.generate(),
            title: title ?? defaultTitle,
            startedAt: now,
            status: .recording
        )
    }
}

// MARK: - GRDB Record Conformance

extension Meeting: FetchableRecord, PersistableRecord {
    static let databaseTableName = "meeting"

    enum Columns: String, ColumnExpression {
        case id, title, startedAt, endedAt, durationMs, audioPath, status, processed
    }
}
