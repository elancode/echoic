import Foundation
import GRDB

/// Wires transcription output to GRDB — inserts segments as they arrive.
/// Supports live FTS search during recording.
final class TranscriptionStore {
    private let databaseWriter: any DatabaseWriter
    private var recentSegments: [TranscriptSegment] = []

    init(databaseWriter: any DatabaseWriter) {
        self.databaseWriter = databaseWriter
    }

    /// Inserts a new transcript segment, deduplicating against recent segments.
    func insert(_ segment: TranscriptSegment) throws {
        // Check for duplicates
        guard !TranscriptDeduplicator.isDuplicate(segment, of: recentSegments) else {
            return
        }

        var mutableSegment = segment
        try databaseWriter.write { db in
            try mutableSegment.insert(db)
        }

        // Track for dedup
        recentSegments.append(mutableSegment)
        // Keep only last 20 segments in memory for dedup checks
        if recentSegments.count > 20 {
            recentSegments.removeFirst(recentSegments.count - 20)
        }
    }

    /// Fetches all segments for a meeting, ordered by start time.
    func segments(for meetingId: String) throws -> [TranscriptSegment] {
        try databaseWriter.read { db in
            try TranscriptSegment
                .filter(TranscriptSegment.Columns.meetingId == meetingId)
                .order(TranscriptSegment.Columns.startMs)
                .fetchAll(db)
        }
    }

    /// Searches transcripts using FTS5 full-text search.
    func search(query: String, meetingId: String? = nil) throws -> [TranscriptSegment] {
        try databaseWriter.read { db in
            var sql = """
                SELECT transcriptSegment.* FROM transcriptSegment
                JOIN transcriptFts ON transcriptFts.rowid = transcriptSegment.id
                WHERE transcriptFts MATCH ?
                """
            var arguments: [DatabaseValueConvertible] = [query]

            if let meetingId {
                sql += " AND transcriptSegment.meetingId = ?"
                arguments.append(meetingId)
            }

            sql += " ORDER BY transcriptSegment.startMs"

            return try TranscriptSegment.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        }
    }

    /// Resets the dedup cache (call when starting a new meeting).
    func resetCache() {
        recentSegments = []
    }
}
