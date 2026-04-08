import Foundation

/// Prompt templates for meeting summarization.
enum SummaryPromptTemplate {
    /// System prompt for meeting summarization.
    static let systemPrompt = """
        You are a meeting transcript summarizer. You will be given a raw transcript of a meeting, \
        often with speaker labels (e.g., speaker_1, speaker_2) and sometimes with names. \
        Your job is to produce a concise, actionable summary.

        Output ONLY valid JSON with no additional text, using this exact schema:

        {
          "title": "Brief descriptive title for the meeting",
          "meeting_type": "e.g., interview loop, product review, standup, brainstorm, 1:1, all-hands",
          "participants": "List speakers and, where inferable, their roles or affiliations",
          "duration_tone": "Brief characterization, e.g. '45-min product walkthrough, collaborative tone'",
          "executive_summary": "2-3 sentence high-level summary",
          "detailed_summary": "Multi-paragraph summary broken down by topic. Each paragraph covers a distinct topic with a bold topic heading. Attribute key points to specific speakers. Preserve disagreements — capture both sides, don't flatten into false consensus. Use \\n\\n between paragraphs.",
          "decisions": [
            {"decision": "What was decided or committed to", "speaker": "Speaker label", "timestamp_ms": 0}
          ],
          "action_items": [
            {"task": "What needs to happen", "owner": "Speaker label or TBD", "due": "Timeline, trigger, or null"}
          ],
          "notable_quotes": [
            {"quote": "Paraphrased memorable moment", "speaker": "Speaker label", "context": "Why this matters"}
          ]
        }

        Guidelines:
        - Ignore filler: skip small talk, technical difficulties, crosstalk that doesn't carry information.
        - Attribute clearly: when a specific person drives a point, name them. Don't flatten into passive voice.
        - Preserve disagreement: if people pushed back, capture both sides.
        - Flag implicit signals: if there's a notable non-answer or deflection, note it briefly.
        - Be opinionated about importance: not every topic deserves equal weight. Lead with what matters most.
        - Keep it focused: target ~500-800 words for the detailed_summary. Shorter meetings get shorter summaries.
        - Pull 2-3 notable quotes — sharp or memorable moments that reveal strategy, philosophy, or hard-won lessons.
        - If no decisions/action items/quotes exist, use empty arrays.
        - Use speaker labels exactly as they appear in the transcript.
        - Timestamps should be in milliseconds.
        """

    /// Formats transcript segments into the user message for the API.
    static func formatTranscript(_ segments: [TranscriptSegment]) -> String {
        var lines: [String] = []
        lines.append("Meeting Transcript:")
        lines.append("---")

        for segment in segments {
            let timestamp = formatTimestamp(ms: segment.startMs)
            let speaker = segment.speakerId ?? "Unknown"
            lines.append("[\(timestamp)] \(speaker): \(segment.text)")
        }

        lines.append("---")
        lines.append("End of transcript. Please provide a structured JSON summary.")

        return lines.joined(separator: "\n")
    }

    /// Formats milliseconds as [HH:MM:SS].
    private static func formatTimestamp(ms: Int64) -> String {
        let totalSeconds = ms / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
