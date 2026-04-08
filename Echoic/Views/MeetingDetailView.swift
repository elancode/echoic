import AppKit
import SwiftUI
import GRDB

struct MeetingDetailView: View {
    let meeting: Meeting

    private enum Tab {
        case transcript, summary
    }

    @State private var selectedTab: Tab = .summary
    @State private var segments: [TranscriptSegment] = []
    @State private var summary: Summary?
    @State private var summaryResponse: SummaryResponse?
    @State private var copiedTranscript = false
    @State private var copiedSummary = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack {
                    Label(
                        Date(timeIntervalSince1970: Double(meeting.startedAt) / 1000).meetingDisplayString,
                        systemImage: "calendar"
                    )

                    if let duration = meeting.durationMs {
                        Label(Date.formatDuration(ms: duration), systemImage: "clock")
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Summary").tag(Tab.summary)
                Text("Transcript").tag(Tab.transcript)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)

            Divider()

            // Tab content
            switch selectedTab {
            case .transcript:
                transcriptTab
            case .summary:
                summaryTab
            }
        }
        .onAppear(perform: loadData)
        .onChange(of: meeting) { _ in loadData() }
    }

    // MARK: - Transcript Tab

    @ViewBuilder
    private var transcriptTab: some View {
        if segments.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "text.alignleft")
                    .font(.title)
                    .foregroundColor(.secondary)
                Text("No Transcript")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: copyTranscript) {
                        Label(copiedTranscript ? "Copied" : "Copy Transcript", systemImage: copiedTranscript ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.trailing)
                    .padding(.vertical, 4)
                }

                ScrollView {
                    Text(Self.buildTranscriptText(from: segments))
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
        }
    }

    // MARK: - Summary Tab

    @ViewBuilder
    private var summaryTab: some View {
        if let response = summaryResponse {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button(action: copySummary) {
                        Label(copiedSummary ? "Copied" : "Copy Summary", systemImage: copiedSummary ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .padding(.trailing)
                    .padding(.vertical, 4)
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Meeting overview
                    if response.meetingType != nil || response.participants != nil || response.durationTone != nil {
                        VStack(alignment: .leading, spacing: 4) {
                            if let type = response.meetingType {
                                HStack(alignment: .top, spacing: 4) {
                                    Text("Type:").fontWeight(.medium)
                                    Text(type)
                                }
                                .font(.subheadline)
                            }
                            if let participants = response.participants {
                                HStack(alignment: .top, spacing: 4) {
                                    Text("Participants:").fontWeight(.medium)
                                    Text(participants)
                                }
                                .font(.subheadline)
                            }
                            if let tone = response.durationTone {
                                Text(tone)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .textSelection(.enabled)
                        Divider()
                    }

                    // Executive summary
                    Text(response.executiveSummary)
                        .textSelection(.enabled)
                        .fontWeight(.medium)

                    // Detailed summary
                    if let detailed = response.detailedSummary, !detailed.isEmpty {
                        Divider()
                        Text(detailed)
                            .textSelection(.enabled)
                    }

                    // Decisions
                    if !response.decisions.isEmpty {
                        SectionHeader(title: "Decisions", icon: "checkmark.seal")
                        ForEach(response.decisions, id: \.decision) { decision in
                            HStack(alignment: .top) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading) {
                                    Text(decision.decision)
                                        .textSelection(.enabled)
                                    if let speaker = decision.speaker {
                                        Text(speaker)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    // Action items
                    if !response.actionItems.isEmpty {
                        SectionHeader(title: "Action Items", icon: "checklist")
                        ForEach(response.actionItems, id: \.task) { item in
                            HStack(alignment: .top) {
                                Image(systemName: "square")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading) {
                                    Text(item.task)
                                        .textSelection(.enabled)
                                    HStack {
                                        if let owner = item.owner {
                                            Text(owner)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        if let due = item.due {
                                            Text("Due: \(due)")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Notable quotes
                    if let quotes = response.notableQuotes, !quotes.isEmpty {
                        SectionHeader(title: "Notable Quotes", icon: "quote.bubble")
                        ForEach(Array(quotes.enumerated()), id: \.offset) { _, quote in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\"\(quote.quote)\"")
                                    .italic()
                                    .textSelection(.enabled)
                                HStack {
                                    if let speaker = quote.speaker {
                                        Text("— \(speaker)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    if let context = quote.context {
                                        Text(context)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text")
                    .font(.title)
                    .foregroundColor(.secondary)
                Text("No Summary")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    /// Builds transcript text, grouping consecutive segments by speaker.
    /// When speakers differ, inserts a blank line and a speaker label.
    /// When no speaker IDs exist, just joins all text with spaces.
    static func buildTranscriptText(from segments: [TranscriptSegment]) -> Swift.String {
        let hasSpeakers = segments.contains { $0.speakerId != nil }
        guard hasSpeakers else {
            return segments.map(\.text).joined(separator: " ")
        }

        var parts: [Swift.String] = []
        var currentSpeaker: Swift.String?
        var currentTexts: [Swift.String] = []

        for segment in segments {
            let speaker = segment.speakerId ?? "Unknown"
            if speaker != currentSpeaker {
                // Flush previous speaker's text
                if !currentTexts.isEmpty {
                    let label = currentSpeaker ?? "Unknown"
                    parts.append("\(label):\n\(currentTexts.joined(separator: " "))")
                }
                currentSpeaker = speaker
                currentTexts = [segment.text]
            } else {
                currentTexts.append(segment.text)
            }
        }
        // Flush last speaker
        if !currentTexts.isEmpty {
            let label = currentSpeaker ?? "Unknown"
            parts.append("\(label):\n\(currentTexts.joined(separator: " "))")
        }

        return parts.joined(separator: "\n\n")
    }

    private func copyTranscript() {
        let transcriptText: Swift.String = Self.buildTranscriptText(from: segments)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcriptText, forType: .string)
        copiedTranscript = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedTranscript = false
        }
    }

    private func copySummary() {
        guard let response = summaryResponse else { return }
        let text = Self.buildSummaryText(from: response)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        copiedSummary = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedSummary = false
        }
    }

    static func buildSummaryText(from response: SummaryResponse) -> Swift.String {
        var parts: [Swift.String] = []

        if let type = response.meetingType {
            parts.append("Type: \(type)")
        }
        if let participants = response.participants {
            parts.append("Participants: \(participants)")
        }

        parts.append("")
        parts.append(response.executiveSummary)

        if let detailed = response.detailedSummary, !detailed.isEmpty {
            parts.append("")
            parts.append(detailed)
        }

        if !response.decisions.isEmpty {
            parts.append("")
            parts.append("Decisions:")
            for d in response.decisions {
                let speaker = d.speaker.map { " (\($0))" } ?? ""
                parts.append("- \(d.decision)\(speaker)")
            }
        }

        if !response.actionItems.isEmpty {
            parts.append("")
            parts.append("Action Items:")
            for item in response.actionItems {
                var line = "- \(item.task)"
                if let owner = item.owner { line += " [\(owner)]" }
                if let due = item.due { line += " (Due: \(due))" }
                parts.append(line)
            }
        }

        if let quotes = response.notableQuotes, !quotes.isEmpty {
            parts.append("")
            parts.append("Notable Quotes:")
            for q in quotes {
                var line = "- \"\(q.quote)\""
                if let speaker = q.speaker { line += " — \(speaker)" }
                parts.append(line)
            }
        }

        return parts.joined(separator: "\n")
    }

    private func loadData() {
        guard let db = DatabaseManager.shared.databaseWriter else { return }

        segments = (try? db.read { dbConn in
            try TranscriptSegment
                .filter(TranscriptSegment.Columns.meetingId == meeting.id)
                .order(TranscriptSegment.Columns.startMs)
                .fetchAll(dbConn)
        }) ?? []

        summary = try? db.read { dbConn in
            try Summary.fetchOne(dbConn, key: meeting.id)
        }

        if let rawJson = summary?.rawJson, let data = rawJson.data(using: .utf8) {
            summaryResponse = try? JSONDecoder().decode(SummaryResponse.self, from: data)
        }
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .padding(.top, 4)
    }
}
