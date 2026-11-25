import Foundation

/// Renders a summary as Markdown, for "Copy summary" and "Export".
/// Section order matches the Library summary view.
enum SummaryMarkdown {
    static func render(_ response: SummaryResponse, title: String, labels: [String: String]) -> String {
        var sections: [String] = ["# \(title)"]

        if let type = response.meetingType { sections.append("_\(type)_") }
        sections.append(response.executiveSummary)

        if !response.decisions.isEmpty {
            let lines = response.decisions.map { decision -> String in
                var line = "- \(decision.decision)"
                if let speaker = SpeakerNaming.resolve(decision.speaker, labels: labels) { line += " — \(speaker)" }
                if let ms = decision.timestampMs { line += " \(Date.formatTimestamp(ms: ms))" }
                return line
            }
            sections.append("## Decisions\n" + lines.joined(separator: "\n"))
        }

        if !response.actionItems.isEmpty {
            let lines = response.actionItems.map { item -> String in
                let details = [SpeakerNaming.resolve(item.owner, labels: labels), item.due.map { "due \($0)" }]
                    .compactMap { $0 }
                return "- [ ] \(item.task)" + (details.isEmpty ? "" : " — " + details.joined(separator: ", "))
            }
            sections.append("## Action items\n" + lines.joined(separator: "\n"))
        }

        if let questions = response.openQuestions, !questions.isEmpty {
            sections.append("## Open questions\n" + questions.map { "- \($0)" }.joined(separator: "\n"))
        }

        if let topics = response.topics, !topics.isEmpty {
            let lines = topics.map { "- \(Date.formatTimestamp(ms: $0.timestampMs ?? 0)) \($0.topic)" }
            sections.append("## Topics\n" + lines.joined(separator: "\n"))
        }

        if let detailed = response.detailedSummary, !detailed.isEmpty {
            sections.append("## Notes\n" + detailed)
        }

        if let quotes = response.notableQuotes, !quotes.isEmpty {
            let lines = quotes.map { quote -> String in
                let speaker = SpeakerNaming.resolve(quote.speaker, labels: labels).map { " — \($0)" } ?? ""
                return "> \(quote.quote)\(speaker)"
            }
            sections.append("## Notable quotes\n" + lines.joined(separator: "\n>\n"))
        }

        return sections.joined(separator: "\n\n") + "\n"
    }
}
