import Foundation
import GRDB

/// A speaker identified within a specific meeting, with a user-editable label.
struct MeetingSpeaker: Codable {
    var meetingId: String
    var speakerId: String
    var label: String
}

// MARK: - GRDB Record Conformance

extension MeetingSpeaker: FetchableRecord, PersistableRecord {
    static let databaseTableName = "meetingSpeaker"

    enum Columns: String, ColumnExpression {
        case meetingId, speakerId, label
    }
}
