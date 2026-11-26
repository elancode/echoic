import AppKit
import SwiftUI

/// Live Transcript window (live transcript handover): header with recording
/// controls, the transcript as speaker turns, and the Insights panel.
struct LiveTranscriptView: View {
    @ObservedObject private var coordinator = MeetingCoordinator.shared
    @ObservedObject private var detector = MeetingDetector.shared
    @AppStorage("showLiveInsightsPanel") private var showInsights = true
    @AppStorage(MeetingCoordinator.liveInsightsSettingKey) private var liveInsightsEnabled = true

    private var insightsVisible: Bool { liveInsightsEnabled && showInsights }

    var body: some View {
        VStack(spacing: 0) {
            LiveHeader(
                coordinator: coordinator,
                appName: detector.recordingAppName,
                showInsights: liveInsightsEnabled ? $showInsights : nil
            )
            Rectangle().fill(Theme.hairline).frame(height: 1)
            GeometryReader { geometry in
                if geometry.size.width < 820 {
                    VStack(spacing: 0) {
                        transcriptColumn
                        if insightsVisible { LiveInsightsPanel().frame(height: min(320, geometry.size.height * 0.45)) }
                    }
                } else {
                    HStack(spacing: 0) {
                        transcriptColumn.frame(minWidth: 480)
                        if insightsVisible { LiveInsightsPanel().frame(width: 340) }
                    }
                }
            }
        }
        .background(Theme.surface)
        .preferredColorScheme(.light)
        .frame(minWidth: 520, minHeight: 420)
    }

    private var transcriptColumn: some View {
        LiveTranscriptColumn(
            state: coordinator.state,
            segments: coordinator.liveSegments,
            bookmarks: coordinator.bookmarks,
            sources: coordinator.activeSourcesDescription
        )
    }
}

// MARK: - Header

private struct LiveHeader: View {
    @ObservedObject var coordinator: MeetingCoordinator
    let appName: String?
    /// `nil` when live insights are turned off in Settings.
    let showInsights: Binding<Bool>?

    var body: some View {
        HStack(spacing: 12) {
            status
            Spacer(minLength: 12)
            if coordinator.state == .recording {
                Button(action: coordinator.addBookmark) {
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark").accessibilityHidden(true)
                        Text("Bookmark")
                        Text("⌘B").font(.mono(11)).foregroundColor(Theme.textMuted).accessibilityHidden(true)
                    }
                }
                .buttonStyle(InkButtonStyle(kind: .secondary, height: 34))
                .keyboardShortcut("b", modifiers: .command)
                .accessibilityLabel("Bookmark this moment")
                Button(action: coordinator.toggleRecording) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill").font(.system(size: 10)).accessibilityHidden(true)
                        Text("Stop and summarize")
                    }
                }
                .buttonStyle(InkButtonStyle(kind: .primary, height: 34))
            }
            if let showInsights {
                Button { showInsights.wrappedValue.toggle() } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.ink)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(showInsights.wrappedValue ? Theme.chip : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showInsights.wrappedValue ? "Hide insights" : "Show insights")
                .accessibilityAddTraits(showInsights.wrappedValue ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var status: some View {
        switch coordinator.state {
        case .recording:
            HStack(spacing: 12) {
                LiveDot(size: 10, pulses: true)
                Text("Recording").font(.display(16)).foregroundColor(Theme.ink)
                LiveElapsedTime(startedAt: coordinator.currentMeeting?.startedAt)
                if let appName {
                    Text(appName).font(.inter(13)).foregroundColor(Theme.textMuted)
                }
            }
        case .processing:
            HStack(spacing: 8) {
                LiveDot(size: 8, pulses: true)
                Text("Summarizing the meeting…").font(.display(16)).foregroundColor(Theme.ink)
            }
        case .idle, .error:
            Text("No meeting in progress").font(.display(16)).foregroundColor(Theme.textMuted)
        }
    }
}

/// Elapsed time, mono 16 in accent.
private struct LiveElapsedTime: View {
    let startedAt: Int64?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = startedAt.map { max(0, Int(context.date.timeIntervalSince1970 - Double($0) / 1000)) } ?? 0
            Text(Self.format(seconds))
                .font(.mono(16, weight: .medium))
                .monospacedDigit()
                .foregroundColor(Theme.accentText)
                .accessibilityLabel("Recording time \(Self.format(seconds))")
        }
    }

    static func format(_ seconds: Int) -> String {
        seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - Transcript column

private struct LiveTranscriptColumn: View {
    let state: MeetingState
    let segments: [TranscriptSegment]
    let bookmarks: [Int64]
    let sources: String

    @State private var isFollowing = true
    @State private var lastAutoScroll = Date.distantPast
    @State private var viewportHeight: CGFloat = 0
    @State private var contentBottom: CGFloat = 0

    private static let bottomId = "live-bottom"
    private static let space = "live-scroll"

    var body: some View {
        let turns = LiveTimeline.turns(from: segments)
        VStack(spacing: 0) {
            if turns.isEmpty {
                LiveEmptyState(state: state)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(LiveTimeline.items(turns: turns, bookmarks: bookmarks)) { item in
                                row(item, isCurrent: item.turn?.id == turns.last?.id && state == .recording)
                            }
                            BottomMarker(space: Self.space).id(Self.bottomId)
                        }
                        .padding(.top, 28)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 20)
                        .textSelection(.enabled)
                    }
                    .coordinateSpace(name: Self.space)
                    .background(GeometryReader { geo in
                        Color.clear
                            .onAppear { viewportHeight = geo.size.height; updateFollowing() }
                            .onChange(of: geo.size.height) { viewportHeight = $0; updateFollowing() }
                    })
                    .onPreferenceChange(BottomOffsetKey.self) { bottom in
                        contentBottom = bottom
                        updateFollowing()
                    }
                    .onAppear { scrollToBottom(proxy, animated: false) }
                    .onChange(of: segments.count) { _ in
                        if isFollowing { scrollToBottom(proxy, animated: true) }
                        announceCompletedTurn(turns)
                    }
                    .onChange(of: bookmarks.count) { _ in
                        if isFollowing { scrollToBottom(proxy, animated: true) }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        LiveFooter(sources: sources, isFollowing: isFollowing) {
                            isFollowing = true
                            scrollToBottom(proxy, animated: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func row(_ item: LiveTimelineItem, isCurrent: Bool) -> some View {
        if let turn = item.turn {
            LiveTurnRow(turn: turn, isCurrent: isCurrent)
        } else {
            BookmarkMarkerRow(ms: item.ms)
        }
    }

    private func updateFollowing() {
        guard viewportHeight > 0 else { return }
        isFollowing = LiveTimeline.isFollowing(
            current: isFollowing,
            distanceFromBottom: contentBottom - viewportHeight,
            secondsSinceAutoScroll: Date().timeIntervalSince(lastAutoScroll)
        )
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        lastAutoScroll = Date()
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
        } else {
            proxy.scrollTo(Self.bottomId, anchor: .bottom)
        }
    }

    /// Polite live region: announce a turn once it's complete, not every fragment.
    private func announceCompletedTurn(_ turns: [LiveTurn]) {
        guard turns.count >= 2 else { return }
        let finished = turns[turns.count - 2]
        guard let window = NSApp.keyWindow else { return }
        NSAccessibility.post(
            element: window, notification: .announcementRequested,
            userInfo: [.announcement: "\(finished.label): \(finished.paragraphs.joined(separator: " "))",
                       .priority: NSAccessibilityPriorityLevel.medium.rawValue]
        )
    }
}

/// Reports the bottom edge of the content, in the scroll view's coordinate space.
private struct BottomMarker: View {
    let space: String

    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(key: BottomOffsetKey.self, value: geo.frame(in: .named(space)).maxY)
        }
        .frame(height: 1)
    }
}

private struct BottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A speaker turn: name and start time in a 104pt gutter, paragraphs beside it.
private struct LiveTurnRow: View {
    let turn: LiveTurn
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.speakerColor(for: turn.speakerId)).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(turn.label).font(.inter(13, weight: .semibold)).foregroundColor(Theme.ink)
                }
                Text(Self.clock(turn.startMs)).font(.mono(11)).foregroundColor(Theme.textMuted)
            }
            .frame(width: 104, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(turn.paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    let isLast = index == turn.paragraphs.count - 1
                    if isCurrent && isLast {
                        TypingCursorText(text: paragraph)
                    } else {
                        Text(paragraph)
                            .font(.inter(16))
                            .lineSpacing(6)
                            .foregroundColor(isCurrent ? Theme.ink : Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// "08:31" (or "1:08:31") from the meeting start.
    static func clock(_ ms: Int64) -> String {
        let seconds = Int(max(0, ms) / 1000)
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// The current turn's last paragraph with an accent cursor right after the last word.
/// The cursor pulses (1.6 s cycle) unless Reduce Motion is on.
private struct TypingCursorText: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.8)) { context in
            let dim = !reduceMotion && Int(context.date.timeIntervalSinceReferenceDate / 0.8) % 2 == 1
            (Text(text).foregroundColor(Theme.ink)
                + Text(" \u{258F}").foregroundColor(Theme.accentFill.opacity(dim ? 0.25 : 1)))
                .font(.inter(16))
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(text)
        }
    }
}

/// "Bookmark · 08:31" with a rule, indented to the text column.
private struct BookmarkMarkerRow: View {
    let ms: Int64

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bookmark.fill").font(.system(size: 11)).foregroundColor(Theme.accentText).accessibilityHidden(true)
            Text("Bookmark · \(LiveTurnRow.clock(ms))").font(.mono(11)).foregroundColor(Theme.accentText)
            Rectangle().fill(Color(hex: 0xF1D5CB)).frame(height: 1)
        }
        .padding(.leading, 124)
        .accessibilityElement(children: .combine)
    }
}

/// Sources on the left; "Following live" / "Jump to live" on the right.
private struct LiveFooter: View {
    let sources: String
    let isFollowing: Bool
    let onJump: () -> Void

    var body: some View {
        HStack {
            Text(sources).font(.mono(11)).foregroundColor(Theme.textMuted)
            Spacer()
            Button(action: onJump) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down").font(.system(size: 11, weight: .semibold)).accessibilityHidden(true)
                    Text(isFollowing ? "Following live" : "Jump to live")
                        .font(.inter(12, weight: isFollowing ? .medium : .semibold))
                }
                .foregroundColor(isFollowing ? Theme.textSecondary : Theme.ink)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().strokeBorder(isFollowing ? Theme.border : Theme.ink, lineWidth: 1))
                .contentShape(Capsule())
                .padding(1)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isFollowing ? [.isSelected] : [])
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 10)
        .background(Theme.surface.opacity(0.96))
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }
}

private struct LiveEmptyState: View {
    let state: MeetingState

    var body: some View {
        VStack(spacing: 10) {
            AppMark(size: 28, color: Theme.textMuted)
            Text(message)
                .font(.inter(14))
                .foregroundColor(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var message: String {
        switch state {
        case .recording: return "Listening… the transcript appears here as people speak."
        case .processing: return "No live transcript was captured."
        case .idle, .error: return "Start a recording to see the live transcript."
        }
    }
}
