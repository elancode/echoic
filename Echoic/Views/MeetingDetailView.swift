import AppKit
import GRDB
import os.log
import SwiftUI
import UniformTypeIdentifiers

private let detailLogger = Logger(subsystem: "com.echoic.app", category: "MeetingDetail")

/// Library content pane: toolbar (Summary / Transcript, Copy, Export) over the
/// summary document or the transcript.
struct MeetingDetailView: View {
    let meeting: Meeting

    enum Tab: Hashable { case summary, transcript }

    @State private var selectedTab: Tab = .summary
    @State private var segments: [TranscriptSegment] = []
    @State private var response: SummaryResponse?
    @State private var speakerLabels: [String: String] = [:]
    @State private var completedActionItems: Set<String> = []
    @State private var transcriptTarget: Int64?
    @State private var copied = false
    @State private var namingSpeakerId: String?
    @State private var speakerNameDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            DetailToolbar(
                selectedTab: $selectedTab,
                copyTitle: copied ? "Copied" : (selectedTab == .summary ? "Copy summary" : "Copy transcript"),
                canCopy: selectedTab == .summary ? response != nil : !segments.isEmpty,
                onCopy: copy,
                onExport: export
            )
            Rectangle().fill(Theme.hairline).frame(height: 1)
            switch selectedTab {
            case .summary:
                ScrollView {
                    SummaryDocumentView(
                        document: document,
                        onTimestamp: jumpToTranscript,
                        onToggleActionItem: setActionItem,
                        onNameSpeaker: beginNaming
                    )
                }
            case .transcript:
                TranscriptPane(blocks: TranscriptBlocks.make(from: segments, labels: speakerLabels),
                               scrollTarget: $transcriptTarget)
            }
        }
        .onAppear(perform: loadData)
        .onChange(of: meeting) { _ in loadData() }
        .alert("Name this speaker", isPresented: isNamingSpeaker) {
            TextField("Name", text: $speakerNameDraft)
            Button("Save", action: saveSpeakerName)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Used for this meeting's transcript and summary.")
        }
    }

    // MARK: - Derived state

    private var document: MeetingDocument {
        MeetingDocument(
            meeting: meeting, response: response, labels: speakerLabels,
            speakers: orderedSpeakers, completedActionItems: completedActionItems
        )
    }

    /// "You" first, then other speakers in ID order. Falls back to the speaker IDs
    /// in the transcript for meetings without speaker rows.
    private var orderedSpeakers: [(id: String, label: String)] {
        var ids = Set(speakerLabels.keys)
        if ids.isEmpty { ids = Set(segments.compactMap(\.speakerId)) }
        return ids
            .sorted { lhs, rhs in
                if lhs == TranscriptSegment.localSpeakerId { return true }
                if rhs == TranscriptSegment.localSpeakerId { return false }
                return lhs.localizedStandardCompare(rhs) == .orderedAscending
            }
            .map { ($0, speakerLabels[$0] ?? SpeakerMerge.defaultLabel(for: $0)) }
    }

    private var isNamingSpeaker: Binding<Bool> {
        Binding(get: { namingSpeakerId != nil }, set: { if !$0 { namingSpeakerId = nil } })
    }

    // MARK: - Actions

    private func jumpToTranscript(_ ms: Int64) {
        transcriptTarget = ms
        selectedTab = .transcript
    }

    private func copy() {
        let text = selectedTab == .summary
            ? response.map { SummaryMarkdown.render($0, title: meeting.title, labels: speakerLabels) }
            : Self.buildTranscriptText(from: segments, labels: speakerLabels)
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            copied = false
        }
    }

    /// Saves the summary (if any) and the transcript as one Markdown file.
    private func export() {
        var markdown = response.map { SummaryMarkdown.render($0, title: meeting.title, labels: speakerLabels) }
            ?? "# \(meeting.title)\n"
        if !segments.isEmpty {
            markdown += "\n## Transcript\n\n" + Self.buildTranscriptText(from: segments, labels: speakerLabels) + "\n"
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = Self.exportFileName(for: meeting.title)
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                detailLogger.error("Export failed: \(error.localizedDescription)")
            }
        }
    }

    static func exportFileName(for title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: "-")
        return (cleaned.trimmingCharacters(in: .whitespaces).isEmpty ? "Meeting" : cleaned) + ".md"
    }

    private func setActionItem(_ task: String, done: Bool) {
        guard let db = DatabaseManager.shared.databaseWriter else { return }
        do {
            try db.write { try MeetingAnnotations.setActionItem(task, done: done, meetingId: meeting.id, db: $0) }
            if done { completedActionItems.insert(task) } else { completedActionItems.remove(task) }
        } catch {
            detailLogger.error("Failed to update action item: \(error.localizedDescription)")
        }
    }

    private func beginNaming(_ speakerId: String) {
        speakerNameDraft = ""
        namingSpeakerId = speakerId
    }

    private func saveSpeakerName() {
        guard let speakerId = namingSpeakerId, let db = DatabaseManager.shared.databaseWriter else { return }
        do {
            try db.write { conn in
                // Older meetings may have no speaker row yet.
                let label = SpeakerMerge.defaultLabel(for: speakerId)
                try conn.execute(
                    sql: "INSERT OR IGNORE INTO meetingSpeaker (meetingId, speakerId, label) VALUES (?, ?, ?)",
                    arguments: [meeting.id, speakerId, label]
                )
                try SpeakerNaming.rename(speakerId: speakerId, to: speakerNameDraft, meetingId: meeting.id, db: conn)
            }
            loadData()
        } catch {
            detailLogger.error("Failed to rename speaker: \(error.localizedDescription)")
        }
    }

    // MARK: - Data

    private func loadData() {
        guard let db = DatabaseManager.shared.databaseWriter else { return }
        do {
            try db.read { conn in
                segments = try TranscriptSegment
                    .filter(TranscriptSegment.Columns.meetingId == meeting.id)
                    .order(TranscriptSegment.Columns.startMs)
                    .fetchAll(conn)
                speakerLabels = try SpeakerNaming.labels(meetingId: meeting.id, db: conn)
                completedActionItems = try MeetingAnnotations.completedActionItems(meetingId: meeting.id, db: conn)
                let summary = try Summary.fetchOne(conn, key: meeting.id)
                response = summary.flatMap { try? JSONDecoder().decode(SummaryResponse.self, from: Data($0.rawJson.utf8)) }
            }
        } catch {
            detailLogger.error("Failed to load meeting: \(error.localizedDescription)")
        }
    }

    /// Builds transcript text, grouping consecutive segments by speaker.
    /// When no speaker IDs exist, just joins all text with spaces.
    static func buildTranscriptText(from segments: [TranscriptSegment], labels: [String: String] = [:]) -> String {
        guard segments.contains(where: { $0.speakerId != nil }) else {
            return segments.map(\.text).joined(separator: " ")
        }
        return TranscriptBlocks.make(from: segments, labels: labels)
            .map { "\($0.label):\n\($0.text)" }
            .joined(separator: "\n\n")
    }
}

// MARK: - Toolbar

private struct DetailToolbar: View {
    @Binding var selectedTab: MeetingDetailView.Tab
    let copyTitle: String
    let canCopy: Bool
    let onCopy: () -> Void
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SegmentedTabs(
                tabs: [(MeetingDetailView.Tab.summary, "Summary"), (.transcript, "Transcript")],
                selection: $selectedTab
            )
            Spacer()
            Button(copyTitle, action: onCopy)
                .buttonStyle(InkButtonStyle(kind: .secondary))
                .disabled(!canCopy)
            Button("Export", action: onExport)
                .buttonStyle(InkButtonStyle(kind: .primary))
                .accessibilityLabel("Export as Markdown")
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
    }
}
