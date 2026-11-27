import SwiftUI

/// Everything the summary document needs, loaded by `MeetingDetailView`.
struct MeetingDocument {
    let meeting: Meeting
    let response: SummaryResponse?
    /// Speaker display labels keyed by speaker ID.
    let labels: [String: String]
    /// Speakers in display order ("You" first).
    let speakers: [(id: String, label: String)]
    let completedActionItems: Set<String>
}

/// The summary laid out as a document (handover §4.1, items 2–9), capped at a
/// 760pt reading column.
struct SummaryDocumentView: View {
    let document: MeetingDocument
    let onTimestamp: (Int64) -> Void
    let onToggleActionItem: (String, Bool) -> Void
    let onNameSpeaker: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DocumentHeader(document: document, onNameSpeaker: onNameSpeaker)
            if let response = document.response {
                Text(response.executiveSummary)
                    .font(.inter(18))
                    .lineSpacing(7)
                    .foregroundColor(Theme.ink2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 24)
                SummarySections(
                    response: response, labels: document.labels,
                    completed: document.completedActionItems,
                    onTimestamp: onTimestamp, onToggleActionItem: onToggleActionItem
                )
            } else {
                PendingSummary(status: document.meeting.status).padding(.top, 24)
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.top, 28)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Header (metadata, title, speakers)

private struct DocumentHeader: View {
    let document: MeetingDocument
    let onNameSpeaker: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(metadata)
                .font(.mono(12))
                .foregroundColor(Theme.textMuted)
            Text(document.meeting.title)
                .font(.display(36))
                .tracking(-0.72)
                .lineSpacing(4)
                .foregroundColor(Theme.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !document.speakers.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(document.speakers, id: \.id) { speaker in
                        let unnamed = SpeakerNaming.isUnnamed(speakerId: speaker.id, label: speaker.label)
                        SpeakerChip(
                            name: speaker.label,
                            color: Theme.speakerColor(for: speaker.id),
                            isUnnamed: unnamed,
                            onName: unnamed ? { onNameSpeaker(speaker.id) } : nil
                        )
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var metadata: String {
        let start = Date(timeIntervalSince1970: Double(document.meeting.startedAt) / 1000)
        var parts = [
            start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()),
            start.formatted(date: .omitted, time: .shortened),
        ]
        if let duration = document.meeting.durationMs { parts.append(Date.formatDuration(ms: duration)) }
        if let type = document.response?.meetingType, !type.isEmpty { parts.append(type) }
        return parts.joined(separator: " · ")
    }
}

private struct PendingSummary: View {
    let status: Meeting.Status

    var body: some View {
        switch status {
        case .processing, .recording:
            MeetingStatusLine(status: status)
        case .error, .ready:
            Text("No summary for this meeting. Check Settings → API key, or read the transcript.")
                .font(.inter(15))
                .foregroundColor(Theme.textMuted)
        }
    }
}

// MARK: - Sections

private struct SummarySections: View {
    let response: SummaryResponse
    let labels: [String: String]
    let completed: Set<String>
    let onTimestamp: (Int64) -> Void
    let onToggleActionItem: (String, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !response.decisions.isEmpty {
                DocumentSection(title: "Decisions") {
                    ForEach(Array(response.decisions.enumerated()), id: \.offset) { _, decision in
                        DecisionRow(decision: decision, labels: labels, onTimestamp: onTimestamp)
                    }
                }
            }
            if !response.actionItems.isEmpty {
                DocumentSection(title: "Action items") {
                    ForEach(Array(response.actionItems.enumerated()), id: \.offset) { _, item in
                        ActionItemRow(
                            item: item, labels: labels, isDone: completed.contains(item.task),
                            onToggle: { onToggleActionItem(item.task, $0) }
                        )
                    }
                }
            }
            if let questions = response.openQuestions, !questions.isEmpty {
                DocumentSection(title: "Open questions") {
                    ForEach(Array(questions.enumerated()), id: \.offset) { _, question in
                        BodyText("– \(question)")
                    }
                }
            }
            if let topics = response.topics, !topics.isEmpty {
                DocumentSection(title: "Topics") { TopicsGrid(topics: topics, onTimestamp: onTimestamp) }
            }
            NotesSection(response: response, labels: labels)
        }
    }
}

private struct DocumentSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.display(15))
                .foregroundColor(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(.top, 32)
    }
}

private struct BodyText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.inter(15))
            .lineSpacing(4)
            .foregroundColor(Theme.ink)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A timestamp that jumps into the transcript.
struct TimestampLink: View {
    let ms: Int64
    let action: (Int64) -> Void

    var body: some View {
        Button { action(ms) } label: {
            Text(Date.formatTimestamp(ms: ms))
                .font(.mono(12))
                .foregroundColor(Theme.accentText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Jump to \(Date.formatTimestamp(ms: ms)) in the transcript")
    }
}

private struct DecisionRow: View {
    let decision: SummaryResponse.Decision
    let labels: [String: String]
    let onTimestamp: (Int64) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            BodyText(decision.decision)
            Spacer(minLength: 12)
            if let speaker = SpeakerNaming.resolve(decision.speaker, labels: labels) {
                Text(speaker).font(.inter(12)).foregroundColor(Theme.textMuted)
            }
            if let ms = decision.timestampMs { TimestampLink(ms: ms, action: onTimestamp) }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

private struct ActionItemRow: View {
    let item: SummaryResponse.ActionItem
    let labels: [String: String]
    let isDone: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Toggle(isOn: Binding(get: { isDone }, set: onToggle)) {
                Text(item.task)
                    .font(.inter(15))
                    .foregroundColor(isDone ? Theme.textMuted : Theme.ink)
                    .strikethrough(isDone, color: Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(InkCheckboxStyle())
            Text(details)
                .font(.inter(12))
                .foregroundColor(Theme.textMuted)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.ground))
    }

    private var details: String {
        [SpeakerNaming.resolve(item.owner, labels: labels), item.due.map { "Due \($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private struct TopicsGrid: View {
    let topics: [SummaryResponse.Topic]
    let onTimestamp: (Int64) -> Void

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(Array(topics.enumerated()), id: \.offset) { _, topic in
                GridRow(alignment: .firstTextBaseline) {
                    TimestampLink(ms: topic.timestampMs ?? 0, action: onTimestamp)
                    BodyText(topic.topic)
                }
            }
        }
    }
}

/// The detailed summary (rendered Markdown, fixing literal `**bold**`) and quotes.
/// Not in the handover's section list; kept so no summary content is lost.
private struct NotesSection: View {
    let response: SummaryResponse
    let labels: [String: String]

    var body: some View {
        if let detailed = response.detailedSummary, !detailed.isEmpty {
            DocumentSection(title: "Notes") {
                Text(Self.markdown(detailed))
                    .font(.inter(15))
                    .lineSpacing(4)
                    .foregroundColor(Theme.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if let quotes = response.notableQuotes, !quotes.isEmpty {
            DocumentSection(title: "Notable quotes") {
                ForEach(Array(quotes.enumerated()), id: \.offset) { _, quote in
                    VStack(alignment: .leading, spacing: 2) {
                        BodyText("“\(quote.quote)”")
                        if let speaker = SpeakerNaming.resolve(quote.speaker, labels: labels) {
                            Text(speaker).font(.inter(12)).foregroundColor(Theme.textMuted)
                        }
                    }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.borderSoft).frame(width: 2) }
                }
            }
        }
    }

    static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
