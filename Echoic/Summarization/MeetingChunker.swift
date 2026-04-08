import Foundation

/// Chunks long meetings (>3 hours) into 90-minute segments for summarization,
/// then consolidates into a meta-summary.
enum MeetingChunker {
    private static let maxDurationMs: Int64 = 3 * 60 * 60 * 1000 // 3 hours
    private static let chunkDurationMs: Int64 = 90 * 60 * 1000   // 90 minutes

    /// Determines if a meeting needs chunking.
    static func needsChunking(durationMs: Int64) -> Bool {
        durationMs > maxDurationMs
    }

    /// Splits transcript segments into 90-minute chunks.
    static func chunk(_ segments: [TranscriptSegment]) -> [[TranscriptSegment]] {
        guard let firstStart = segments.first?.startMs,
              let lastEnd = segments.last?.endMs else {
            return [segments]
        }

        let totalDuration = lastEnd - firstStart
        guard totalDuration > maxDurationMs else {
            return [segments]
        }

        var chunks: [[TranscriptSegment]] = []
        var currentChunk: [TranscriptSegment] = []
        var chunkStart = firstStart

        for segment in segments {
            if segment.startMs >= chunkStart + chunkDurationMs && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = []
                chunkStart = segment.startMs
            }
            currentChunk.append(segment)
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks
    }

    /// Prompt for consolidating chunk summaries into a meta-summary.
    static let metaSummaryPrompt = """
        You are consolidating multiple partial meeting summaries into one comprehensive summary. \
        Each partial summary covers a 90-minute segment of a long meeting.

        Combine them into a single structured JSON summary using the same schema. \
        Merge duplicate decisions and action items. Resolve any contradictions by preferring later segments. \
        Produce a unified executive summary that covers the entire meeting.

        Output ONLY valid JSON.
        """

    /// Formats chunk summaries for the meta-summary prompt.
    static func formatChunkSummaries(_ summaries: [SummaryResponse]) -> String {
        var text = "Partial Meeting Summaries:\n\n"

        for (i, summary) in summaries.enumerated() {
            text += "--- Part \(i + 1) of \(summaries.count) ---\n"
            if let data = try? JSONEncoder().encode(summary),
               let json = String(data: data, encoding: .utf8) {
                text += json + "\n\n"
            }
        }

        text += "Please consolidate these into a single comprehensive meeting summary."
        return text
    }
}
