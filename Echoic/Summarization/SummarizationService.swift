import Foundation
import GRDB

/// Orchestrates the full summarization pipeline:
/// transcript → (optional chunking) → API call → parse → store in GRDB.
final class SummarizationService {
    private let client: AnthropicClient
    private let databaseWriter: any DatabaseWriter

    init(client: AnthropicClient = AnthropicClient(), databaseWriter: any DatabaseWriter) {
        self.client = client
        self.databaseWriter = databaseWriter
    }

    /// Summarizes a meeting and stores the result.
    func summarize(meetingId: String) async throws {
        // Fetch transcript segments
        let segments = try await databaseWriter.read { db in
            try TranscriptSegment
                .filter(TranscriptSegment.Columns.meetingId == meetingId)
                .order(TranscriptSegment.Columns.startMs)
                .fetchAll(db)
        }

        guard !segments.isEmpty else { return }

        let response: SummaryResponse

        // Check if chunking is needed
        let totalDuration = (segments.last?.endMs ?? 0) - (segments.first?.startMs ?? 0)

        if MeetingChunker.needsChunking(durationMs: totalDuration) {
            response = try await summarizeLongMeeting(segments: segments)
        } else {
            response = try await summarizeChunk(segments: segments)
        }

        // Store in database
        try await storeSummary(response: response, meetingId: meetingId)

        // Update meeting title if we got a better one
        try await databaseWriter.write { db in
            if var meeting = try Meeting.fetchOne(db, key: meetingId) {
                meeting.title = response.title
                try meeting.update(db)
            }
        }
    }

    // MARK: - Private

    private func summarizeChunk(segments: [TranscriptSegment]) async throws -> SummaryResponse {
        let transcript = SummaryPromptTemplate.formatTranscript(segments)

        return try await RetryHandler.withRetry {
            try await client.summarize(
                transcript: transcript,
                systemPrompt: SummaryPromptTemplate.systemPrompt
            )
        }
    }

    private func summarizeLongMeeting(segments: [TranscriptSegment]) async throws -> SummaryResponse {
        let chunks = MeetingChunker.chunk(segments)
        var chunkSummaries: [SummaryResponse] = []

        for chunk in chunks {
            let summary = try await summarizeChunk(segments: chunk)
            chunkSummaries.append(summary)
        }

        // Consolidate chunk summaries
        let consolidationText = MeetingChunker.formatChunkSummaries(chunkSummaries)

        return try await RetryHandler.withRetry {
            try await client.summarize(
                transcript: consolidationText,
                systemPrompt: MeetingChunker.metaSummaryPrompt
            )
        }
    }

    private func storeSummary(response: SummaryResponse, meetingId: String) async throws {
        let rawJson: String
        if let data = try? JSONEncoder().encode(response),
           let json = String(data: data, encoding: .utf8) {
            rawJson = json
        } else {
            rawJson = "{}"
        }

        let summary = Summary(
            meetingId: meetingId,
            rawJson: rawJson,
            executiveSummary: response.executiveSummary,
            title: response.title,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000)
        )

        try await databaseWriter.write { db in
            try summary.insert(db)
        }
    }
}
