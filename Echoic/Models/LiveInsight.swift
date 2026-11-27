import Foundation
import GRDB

/// A snapshot of the live insights agent's view of an in-progress meeting:
/// a running recap plus the open concerns and questions in the current discussion.
struct LiveInsight: Codable, Identifiable, Equatable {
    var id: Int64?
    var meetingId: String
    /// Unix epoch milliseconds when this snapshot was generated.
    var createdAt: Int64
    /// Transcript end time (ms from meeting start) covered by this snapshot.
    var coversUntilMs: Int64
    var recap: String
    var concerns: [String]
    var questions: [String]
}

// MARK: - GRDB Record Conformance

extension LiveInsight: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "liveInsight"

    enum Columns: String, ColumnExpression {
        case id, meetingId, createdAt, coversUntilMs, recap, concerns, questions
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - API Response

/// JSON returned by the model for a live insight update.
struct LiveInsightResponse: Codable, Equatable {
    let hasUpdate: Bool
    let recap: String?
    let concerns: [String]?
    let questions: [String]?

    init(hasUpdate: Bool, recap: String? = nil, concerns: [String]? = nil, questions: [String]? = nil) {
        self.hasUpdate = hasUpdate
        self.recap = recap
        self.concerns = concerns
        self.questions = questions
    }

    enum CodingKeys: String, CodingKey {
        case hasUpdate = "has_update"
        case recap, concerns, questions
    }
}
