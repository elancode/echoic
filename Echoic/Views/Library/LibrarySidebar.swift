import SwiftUI

/// Library sidebar: app header with Record, search, date filters, and meetings
/// grouped by day (handover §4.1).
struct LibrarySidebar: View {
    let groups: [MeetingGroup]
    let speakerCounts: [String: Int]
    @Binding var searchText: String
    @Binding var dateFilter: LibraryDateFilter
    @Binding var selectedMeetingId: String?
    let onDelete: (Meeting) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarHeader()
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            SidebarSearchField(text: $searchText)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            FilterBar(selection: $dateFilter)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            MeetingList(
                groups: groups,
                speakerCounts: speakerCounts,
                isSearching: !searchText.isEmpty,
                selectedMeetingId: $selectedMeetingId,
                onDelete: onDelete
            )
        }
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.ground)
    }
}

enum LibraryDateFilter: String, CaseIterable {
    case all = "All"
    case today = "Today"
    case thisWeek = "This week"
    case thisMonth = "This month"
}

// MARK: - Header

private struct SidebarHeader: View {
    @ObservedObject private var coordinator = MeetingCoordinator.shared

    var body: some View {
        HStack(spacing: 8) {
            AppMark(size: 20)
            Text("Echoic")
                .font(.display(18))
                .foregroundColor(Theme.ink)
            Spacer()
            Button(action: coordinator.toggleRecording) {
                HStack(spacing: 6) {
                    LiveDot(size: 7, pulses: isRecording)
                    Text(isRecording ? "Stop" : "Record")
                }
            }
            .buttonStyle(InkButtonStyle(kind: .secondary, height: 28))
            .keyboardShortcut("r", modifiers: .command)
            .disabled(coordinator.state == .processing)
            .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        }
    }

    private var isRecording: Bool { coordinator.state == .recording }
}

// MARK: - Search

private struct SidebarSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textMuted)
                .accessibilityHidden(true)
            TextField("Search every meeting", text: $text)
                .textFieldStyle(.plain)
                .font(.inter(13))
                .foregroundColor(Theme.ink)
                .focused($isFocused)
                .accessibilityLabel("Search every meeting")
            if text.isEmpty {
                Text("⌘K")
                    .font(.mono(11))
                    .foregroundColor(Theme.textMuted)
                    .accessibilityHidden(true)
            } else {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(Theme.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Theme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(isFocused ? Theme.ink : Theme.border, lineWidth: isFocused ? 2 : 1)
        )
        .background(
            // ⌘K focuses search
            Button("") { isFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        )
    }
}

// MARK: - Filters

private struct FilterBar: View {
    @Binding var selection: LibraryDateFilter

    var body: some View {
        HStack(spacing: 4) {
            ForEach(LibraryDateFilter.allCases, id: \.self) { filter in
                FilterPill(title: filter.rawValue, isSelected: filter == selection) {
                    selection = filter
                }
            }
        }
    }
}

// MARK: - List

private struct MeetingList: View {
    let groups: [MeetingGroup]
    let speakerCounts: [String: Int]
    let isSearching: Bool
    @Binding var selectedMeetingId: String?
    let onDelete: (Meeting) -> Void

    var body: some View {
        if groups.isEmpty {
            Text(isSearching ? "No meetings match your search." : "No meetings yet. Press Record to start one.")
                .font(.inter(13))
                .foregroundColor(Theme.textMuted)
                .padding(16)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(groups) { group in
                        GroupLabel(group.title)
                            .padding(.horizontal, 12)
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                        ForEach(group.meetings, id: \.id) { meeting in
                            MeetingRow(
                                meeting: meeting,
                                speakerCount: speakerCounts[meeting.id],
                                isSelected: meeting.id == selectedMeetingId
                            ) { selectedMeetingId = meeting.id }
                            .contextMenu {
                                Button("Delete Meeting…", role: .destructive) { onDelete(meeting) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
    }
}

/// Meeting row: wrapping title over a mono line of time, duration and speakers.
/// Shows an accent status line only while something is in progress.
struct MeetingRow: View {
    let meeting: Meeting
    let speakerCount: Int?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(.inter(14, weight: .medium))
                    .foregroundColor(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(metadata)
                    .font(.mono(11))
                    .foregroundColor(Theme.textMuted)
                MeetingStatusLine(status: meeting.status)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(isSelected ? Theme.surface : .clear)
                    .shadow(color: isSelected ? Theme.ink.opacity(0.06) : .clear, radius: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .strokeBorder(isSelected ? Theme.borderSoft : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var metadata: String {
        let start = Date(timeIntervalSince1970: Double(meeting.startedAt) / 1000)
        var parts = [start.formatted(date: .omitted, time: .shortened)]
        if let duration = meeting.durationMs { parts.append(Date.formatDuration(ms: duration)) }
        if let count = speakerCount, count > 0 { parts.append(count == 1 ? "1 speaker" : "\(count) speakers") }
        return parts.joined(separator: " · ")
    }
}

/// "Recording" / "Summarizing" in accent while in progress; nothing when ready.
struct MeetingStatusLine: View {
    let status: Meeting.Status

    var body: some View {
        switch status {
        case .recording:
            label("Recording", live: true)
        case .processing:
            label("Summarizing", live: true)
        case .error:
            label("Summary unavailable", live: false)
        case .ready:
            EmptyView()
        }
    }

    private func label(_ text: String, live: Bool) -> some View {
        HStack(spacing: 6) {
            if live { LiveDot(size: 6, pulses: true) }
            Text(text)
                .font(.inter(12, weight: .medium))
                .foregroundColor(live ? Theme.accentText : Theme.textMuted)
        }
    }
}
