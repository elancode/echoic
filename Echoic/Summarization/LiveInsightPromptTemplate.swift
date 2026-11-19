import Foundation

/// Prompt for the live insights agent. The agent keeps a rolling state: each call
/// sends its previous state plus only the transcript added since, so request size
/// stays roughly constant no matter how long the meeting runs.
enum LiveInsightPromptTemplate {
    static let systemPrompt = """
        You are a live meeting copilot. You read a meeting transcript while the meeting is happening \
        and help one participant (labeled "You") keep track of a complex discussion.

        You receive:
        - MEETING CONTEXT (optional): a note from the user about what the meeting is for.
        - PREVIOUS STATE: your last recap, open concerns, and questions (may be empty).
        - EARLIER CONTEXT: transcript lines you have already seen, for continuity.
        - NEW TRANSCRIPT: lines spoken since your last update.

        Return an updated state:
        - recap: 2-4 sentences on where the discussion stands now: the current topic, the positions \
        people have taken, and what changed. Plain language.
        - concerns: up to 3 open risks, objections, contradictions, or unresolved disagreements raised in \
        this discussion. Each under 25 words, naming the topic or speaker it relates to.
        - questions: up to 3 questions that are still unanswered, or worth asking next to move the current \
        discussion forward. Each under 25 words.

        Rules:
        - Ground every item in what was actually said. No generic meeting advice, no speculation beyond \
        the transcript.
        - Favor the current topic. Keep earlier items only while they are still unresolved and important; \
        drop items that were resolved or are no longer relevant.
        - The transcript comes from speech recognition and may contain errors. Never flag transcription \
        glitches as concerns. "Others" means remote participants whose speaker is not yet identified.
        - If nothing meaningful changed since the previous state, return {"has_update": false}.

        Respond with JSON only, no prose:
        {"has_update": true, "recap": "...", "concerns": ["..."], "questions": ["..."]}
        """

    /// Builds the user message for one update.
    static func userMessage(
        previous: LiveInsight?,
        contextNote: String,
        earlierSegments: [TranscriptSegment],
        newSegments: [TranscriptSegment]
    ) -> String {
        var sections: [String] = []

        let note = contextNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty {
            sections.append("MEETING CONTEXT:\n\(note)")
        }

        sections.append("PREVIOUS STATE:\n\(formatState(previous))")

        if !earlierSegments.isEmpty {
            sections.append("EARLIER CONTEXT (already seen):\n\(formatLines(earlierSegments))")
        }

        sections.append("NEW TRANSCRIPT:\n\(formatLines(newSegments))")
        return sections.joined(separator: "\n\n")
    }

    // MARK: - Private

    private static func formatState(_ insight: LiveInsight?) -> String {
        guard let insight else { return "(none yet)" }
        var lines = ["Recap: \(insight.recap)", "Concerns:"]
        lines += insight.concerns.isEmpty ? ["(none)"] : insight.concerns.map { "- \($0)" }
        lines.append("Questions:")
        lines += insight.questions.isEmpty ? ["(none)"] : insight.questions.map { "- \($0)" }
        return lines.joined(separator: "\n")
    }

    private static func formatLines(_ segments: [TranscriptSegment]) -> String {
        segments.map { segment in
            let speaker = segment.speakerId == nil ? "Others" : segment.speakerDisplayName
            return "[\(SummaryPromptTemplate.formatTimestamp(ms: segment.startMs))] \(speaker): \(segment.text)"
        }
        .joined(separator: "\n")
    }
}
