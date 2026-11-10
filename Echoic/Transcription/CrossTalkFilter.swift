import Foundation

/// Detects microphone segments that are really other participants' voices
/// picked up from the speakers (when the user isn't wearing headphones).
///
/// System audio is transcribed separately, so a mic segment whose words are
/// mostly already in time-overlapping system segments is treated as bleed.
enum CrossTalkFilter {
    /// Extra time (ms) around the mic segment to search for matching system speech.
    private static let timeToleranceMs: Int64 = 2000

    /// Fraction of the mic segment's words that must appear in system audio.
    private static let containmentThreshold = 0.6

    /// - Parameters:
    ///   - micSegment: A segment transcribed from the local microphone.
    ///   - recent: Recently accepted segments (system and mic).
    /// - Returns: `true` if the mic segment duplicates system audio and should be dropped.
    static func isBleed(_ micSegment: TranscriptSegment, against recent: [TranscriptSegment]) -> Bool {
        let micWords = words(in: micSegment.text)
        guard !micWords.isEmpty else { return false }

        let windowStart = micSegment.startMs - timeToleranceMs
        let windowEnd = micSegment.endMs + timeToleranceMs

        var systemWords = Set<String>()
        for segment in recent where !segment.isLocalSpeaker {
            guard segment.endMs >= windowStart, segment.startMs <= windowEnd else { continue }
            systemWords.formUnion(words(in: segment.text))
        }
        guard !systemWords.isEmpty else { return false }

        let contained = micWords.filter { systemWords.contains($0) }.count
        return Double(contained) / Double(micWords.count) >= containmentThreshold
    }

    /// Lowercased words with punctuation and apostrophes removed.
    private static func words(in text: String) -> Set<String> {
        let normalized = text.lowercased().replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
        let tokens = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Set(tokens.filter { !$0.isEmpty })
    }
}
