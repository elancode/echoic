import GRDB
import os.log
import SwiftUI

private let libraryLogger = Logger(subsystem: "com.echoic.app", category: "Library")

/// Meeting Library: a ~300pt sidebar and an independently scrolling content pane.
struct MeetingLibraryView: View {
    @State private var meetings: [Meeting] = []
    @State private var speakerCounts: [String: Int] = [:]
    @State private var searchText = ""
    @State private var searchMatches: Set<String>?
    @State private var dateFilter: LibraryDateFilter = .all
    @State private var selectedMeetingId: String?
    @State private var pendingDelete: Meeting?

    var body: some View {
        HStack(spacing: 0) {
            LibrarySidebar(
                groups: MeetingGrouping.groups(for: filteredMeetings),
                speakerCounts: speakerCounts,
                searchText: $searchText,
                dateFilter: $dateFilter,
                selectedMeetingId: $selectedMeetingId,
                onDelete: { pendingDelete = $0 }
            )
            .frame(width: 300)

            Rectangle().fill(Theme.borderSoft).frame(width: 1)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.surface)
        }
        .background(Theme.ground.ignoresSafeArea())
        .preferredColorScheme(.light)
        .frame(minWidth: 860, minHeight: 600)
        .onAppear(perform: loadMeetings)
        .onChange(of: searchText) { performSearch($0) }
        .onChange(of: dateFilter) { _ in loadMeetings() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loadMeetings()
        }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in loadMeetings() }
        .confirmationDialog(
            "Delete “\(pendingDelete?.title ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { meeting in
            Button("Delete Meeting", role: .destructive) { deleteMeeting(meeting) }
        } message: { _ in
            Text("The transcript, summary and audio are removed from this Mac. This can't be undone.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let meeting = meetings.first(where: { $0.id == selectedMeetingId }) {
            MeetingDetailView(meeting: meeting).id(meeting.id)
        } else {
            VStack(spacing: 8) {
                AppMark(size: 28, color: Theme.textMuted)
                Text(meetings.isEmpty ? "No meetings yet" : "Select a meeting")
                    .font(.display(15))
                    .foregroundColor(Theme.ink)
                Text(meetings.isEmpty
                     ? "Start a recording from the menu bar or with Record."
                     : "Its summary and transcript open here.")
                    .font(.inter(13))
                    .foregroundColor(Theme.textMuted)
            }
        }
    }

    private var filteredMeetings: [Meeting] {
        guard let matches = searchMatches else { return meetings }
        return meetings.filter { matches.contains($0.id) }
    }

    // MARK: - Data

    private func loadMeetings() {
        guard let db = DatabaseManager.shared.databaseWriter else { return }
        let startMs = dateFilterStart.map { Int64($0.timeIntervalSince1970 * 1000) }
        do {
            let (loaded, counts) = try db.read { conn -> ([Meeting], [String: Int]) in
                var query = Meeting.order(Meeting.Columns.startedAt.desc)
                if let startMs { query = query.filter(Meeting.Columns.startedAt >= startMs) }
                let rows = try Row.fetchAll(conn, sql: "SELECT meetingId, COUNT(*) AS n FROM meetingSpeaker GROUP BY meetingId")
                let counts = Dictionary(uniqueKeysWithValues: rows.map { ($0["meetingId"] as String, $0["n"] as Int) })
                return (try query.fetchAll(conn), counts)
            }
            if loaded != meetings { meetings = loaded }
            if counts != speakerCounts { speakerCounts = counts }
            if selectedMeetingId == nil { selectedMeetingId = loaded.first?.id }
        } catch {
            libraryLogger.error("Failed to load meetings: \(error.localizedDescription)")
        }
    }

    private var dateFilterStart: Date? {
        let calendar = Calendar.current
        switch dateFilter {
        case .all: return nil
        case .today: return calendar.startOfDay(for: Date())
        case .thisWeek: return calendar.date(byAdding: .weekOfYear, value: -1, to: Date())
        case .thisMonth: return calendar.date(byAdding: .month, value: -1, to: Date())
        }
    }

    private func deleteMeeting(_ meeting: Meeting) {
        guard let db = DatabaseManager.shared.databaseWriter else { return }
        do {
            // Foreign keys cascade to segments, summary, speakers, bookmarks and action items.
            _ = try db.write { try Meeting.deleteOne($0, key: meeting.id) }
            try? AudioFileManager.deleteMeetingFiles(meetingId: meeting.id)
            if selectedMeetingId == meeting.id { selectedMeetingId = nil }
            loadMeetings()
        } catch {
            libraryLogger.error("Failed to delete meeting: \(error.localizedDescription)")
        }
    }

    private func performSearch(_ query: String) {
        guard !query.isEmpty, let db = DatabaseManager.shared.databaseWriter else {
            searchMatches = nil
            return
        }
        let results = (try? TranscriptionStore(databaseWriter: db).search(query: query)) ?? []
        let titleMatches = meetings.filter { $0.title.localizedCaseInsensitiveContains(query) }.map(\.id)
        searchMatches = Set(results.map(\.meetingId)).union(titleMatches)
    }
}
