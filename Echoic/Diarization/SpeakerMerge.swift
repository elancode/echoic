import Foundation
import GRDB

/// Merges diarization results with transcript segments.
/// Assigns speaker IDs to each transcript segment by timestamp overlap.
enum SpeakerMerge {
    /// Assigns speaker IDs to transcript segments based on diarization results.
    static func merge(
        meetingId: String,
        speakerSegments: [DiarizationService.DiarizationSegment],
        databaseWriter: any DatabaseWriter
    ) throws {
        try databaseWriter.write { db in
            // Fetch all transcript segments for this meeting
            var transcriptSegments = try TranscriptSegment
                .filter(TranscriptSegment.Columns.meetingId == meetingId)
                .order(TranscriptSegment.Columns.startMs)
                .fetchAll(db)

            for i in 0..<transcriptSegments.count {
                let bestSpeaker = findBestSpeaker(
                    for: transcriptSegments[i],
                    in: speakerSegments
                )

                if let speaker = bestSpeaker {
                    transcriptSegments[i].speakerId = speaker
                    try transcriptSegments[i].update(db)
                }
            }

            // Create meetingSpeaker entries
            let uniqueSpeakers = Set(speakerSegments.map(\.speakerId))
            for speakerId in uniqueSpeakers {
                let label = defaultLabel(for: speakerId)
                let meetingSpeaker = MeetingSpeaker(
                    meetingId: meetingId,
                    speakerId: speakerId,
                    label: label
                )
                try meetingSpeaker.insert(db)
            }
        }
    }

    /// Finds the speaker with the most overlap for a transcript segment.
    private static func findBestSpeaker(
        for segment: TranscriptSegment,
        in speakerSegments: [DiarizationService.DiarizationSegment]
    ) -> String? {
        var bestOverlap: Int64 = 0
        var bestSpeaker: String?

        for speaker in speakerSegments {
            let overlapStart = max(segment.startMs, speaker.startMs)
            let overlapEnd = min(segment.endMs, speaker.endMs)
            let overlap = max(0, overlapEnd - overlapStart)

            if overlap > bestOverlap {
                bestOverlap = overlap
                bestSpeaker = speaker.speakerId
            }
        }

        return bestSpeaker
    }

    /// Returns a default label for a speaker ID.
    private static func defaultLabel(for speakerId: String) -> String {
        if speakerId == "you" { return "You" }

        // "speaker_1" → "Speaker 1"
        if let number = speakerId.split(separator: "_").last {
            return "Speaker \(number)"
        }

        return speakerId.capitalized
    }
}
