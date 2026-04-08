import SwiftUI
import GRDB

struct MeetingLibraryView: View {
    @State private var meetings: [Meeting] = []
    @State private var searchText = ""
    @State private var searchResults: [TranscriptSegment] = []
    @State private var selectedMeeting: Meeting?
    @State private var dateFilter: DateFilter = .all

    enum DateFilter: String, CaseIterable {
        case all = "All"
        case today = "Today"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Date filter
                Picker("Period", selection: $dateFilter) {
                    ForEach(DateFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                // Meeting list
                List(filteredMeetings, selection: $selectedMeeting) { meeting in
                    MeetingCard(meeting: meeting, onDelete: { deleteMeeting(meeting) })
                        .tag(meeting)
                }
                .listStyle(.sidebar)
            }
            .searchable(text: $searchText, prompt: "Search transcripts")
            .onChange(of: searchText) { newValue in
                performSearch(newValue)
            }
            .onChange(of: dateFilter) { _ in
                loadMeetings()
            }
            .navigationTitle("Meetings")
        } detail: {
            if let meeting = selectedMeeting {
                MeetingDetailView(meeting: meeting)
                    .id(meeting.id)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Select a Meeting")
                        .font(.headline)
                    Text("Choose a meeting from the sidebar to view its transcript and summary.")
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear(perform: loadMeetings)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loadMeetings()
        }
        .onReceive(Timer.publish(every: 3, on: .main, in: .common).autoconnect()) { _ in
            loadMeetings()
        }
    }

    private var filteredMeetings: [Meeting] {
        if !searchText.isEmpty {
            let matchingMeetingIds = Set(searchResults.map(\.meetingId))
            return meetings.filter { matchingMeetingIds.contains($0.id) }
        }
        return meetings
    }

    private func loadMeetings() {
        guard let db = DatabaseManager.shared.databaseWriter else { return }

        meetings = (try? db.read { dbConn in
            var query = Meeting.order(Meeting.Columns.startedAt.desc)

            if let startDate = dateFilterStart {
                let startMs = Int64(startDate.timeIntervalSince1970 * 1000)
                query = query.filter(Meeting.Columns.startedAt >= startMs)
            }

            return try query.fetchAll(dbConn)
        }) ?? []
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
            try db.write { dbConn in
                try dbConn.execute(sql: "DELETE FROM transcriptSegment WHERE meetingId = ?", arguments: [meeting.id])
                try dbConn.execute(sql: "DELETE FROM summary WHERE meetingId = ?", arguments: [meeting.id])
                try dbConn.execute(sql: "DELETE FROM meetingSpeaker WHERE meetingId = ?", arguments: [meeting.id])
                try dbConn.execute(sql: "DELETE FROM meeting WHERE id = ?", arguments: [meeting.id])
            }
            try? AudioFileManager.deleteMeetingFiles(meetingId: meeting.id)
            if selectedMeeting?.id == meeting.id {
                selectedMeeting = nil
            }
            loadMeetings()
        } catch {
            print("[Library] Failed to delete meeting: \(error)")
        }
    }

    private func performSearch(_ query: String) {
        guard !query.isEmpty, let db = DatabaseManager.shared.databaseWriter else {
            searchResults = []
            return
        }

        let store = TranscriptionStore(databaseWriter: db)
        searchResults = (try? store.search(query: query)) ?? []
    }
}

// MARK: - Meeting Card

struct MeetingCard: View {
    let meeting: Meeting
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(meeting.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                StatusBadge(status: meeting.status)
                Button(action: { onDelete?() }) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Label(
                    Date(timeIntervalSince1970: Double(meeting.startedAt) / 1000).meetingDisplayString,
                    systemImage: "calendar"
                )
                .font(.caption)
                .foregroundColor(.secondary)

                if let duration = meeting.durationMs {
                    Label(
                        Date.formatDuration(ms: duration),
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
