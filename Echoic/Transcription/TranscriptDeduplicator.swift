import Foundation

/// Deduplicates transcript segments from overlapping chunks.
/// WhisperKit processes 10s chunks with 2s overlap — segments near overlap
/// boundaries may appear twice with slightly different timestamps.
enum TranscriptDeduplicator {
    /// Maximum timestamp difference (ms) to consider two segments as duplicates.
    private static let timestampThresholdMs: Int64 = 1500

    /// Minimum text similarity (0–1) to consider two segments as duplicates.
    private static let similarityThreshold: Double = 0.7

    /// Deduplicates a new segment against existing segments.
    /// - Parameters:
    ///   - candidate: The new segment to check.
    ///   - existing: Previously accepted segments for the same meeting.
    /// - Returns: `true` if the candidate is a duplicate and should be skipped.
    static func isDuplicate(_ candidate: TranscriptSegment, of existing: [TranscriptSegment]) -> Bool {
        for segment in existing.suffix(10) { // Only check recent segments
            let timeOverlap = abs(candidate.startMs - segment.startMs) < timestampThresholdMs
                || abs(candidate.endMs - segment.endMs) < timestampThresholdMs

            guard timeOverlap else { continue }

            let similarity = textSimilarity(candidate.text, segment.text)
            if similarity >= similarityThreshold {
                return true
            }
        }
        return false
    }

    /// Merges a candidate segment with its best-matching existing segment.
    /// Prefers the version with higher confidence.
    static func merge(_ candidate: TranscriptSegment, into existing: inout [TranscriptSegment]) {
        for i in stride(from: existing.count - 1, through: max(0, existing.count - 10), by: -1) {
            let segment = existing[i]
            let timeOverlap = abs(candidate.startMs - segment.startMs) < timestampThresholdMs

            guard timeOverlap else { continue }

            let similarity = textSimilarity(candidate.text, segment.text)
            if similarity >= similarityThreshold {
                // Keep the higher-confidence version
                if (candidate.confidence ?? 0) > (segment.confidence ?? 0) {
                    existing[i] = candidate
                }
                return
            }
        }

        // No duplicate found — append
        existing.append(candidate)
    }

    /// Computes a simple word-level Jaccard similarity between two strings.
    static func textSimilarity(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.lowercased().split(separator: " "))
        let wordsB = Set(b.lowercased().split(separator: " "))

        guard !wordsA.isEmpty || !wordsB.isEmpty else { return 1.0 }

        let intersection = wordsA.intersection(wordsB).count
        let union = wordsA.union(wordsB).count

        return Double(intersection) / Double(union)
    }
}
