import Foundation
import GRDB

/// Applies speaker names inferred by summarization to a meeting's speaker labels,
/// and resolves speaker IDs to display labels.
enum SpeakerNaming {
    /// Renames speakers that still have their default label ("Speaker N").
    /// Labels the user (or local speaker ID) already set, and "You", are kept.
    static func apply(names: [String: String], meetingId: String, db: Database) throws {
        for (speakerId, rawName) in names where speakerId != TranscriptSegment.localSpeakerId {
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            try db.execute(
                sql: "UPDATE meetingSpeaker SET label = ? WHERE meetingId = ? AND speakerId = ? AND label = ?",
                arguments: [name, meetingId, speakerId, SpeakerMerge.defaultLabel(for: speakerId)]
            )
        }
    }

    /// Display labels for a meeting's speakers, keyed by speaker ID.
    static func labels(meetingId: String, db: Database) throws -> [String: String] {
        let speakers = try MeetingSpeaker
            .filter(MeetingSpeaker.Columns.meetingId == meetingId)
            .fetchAll(db)
        return Dictionary(speakers.map { ($0.speakerId, $0.label) }, uniquingKeysWith: { first, _ in first })
    }

    /// Replaces a speaker ID (e.g. a summary's "speaker_1") with its label; other text is unchanged.
    static func resolve(_ speaker: String?, labels: [String: String]) -> String? {
        guard let speaker else { return nil }
        return labels[speaker] ?? speaker
    }
}
