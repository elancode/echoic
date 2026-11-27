import SwiftUI

/// Menu bar popover (handover §4.2–4.3). Light when ready; inverted to ink while
/// recording so the state is unmistakable at a glance.
struct MenuBarPopoverView: View {
    @ObservedObject private var coordinator = MeetingCoordinator.shared
    @ObservedObject private var meetingDetector = MeetingDetector.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if coordinator.state == .recording {
                RecordingPopover(
                    coordinator: coordinator,
                    onSettings: { open("settings") },
                    onLiveTranscript: { open("live-transcript") }
                )
            } else {
                ReadyPopover(
                    coordinator: coordinator,
                    meetingDetector: meetingDetector,
                    onSettings: { open("settings") },
                    onLibrary: { open("library") }
                )
            }
        }
        .frame(width: 340)
        .background(WindowKeyObserver { isOpen in
            if isOpen { meetingDetector.menuOpened() } else { meetingDetector.menuClosed() }
        })
    }

    private func open(_ windowId: String) {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: windowId)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Header

private struct PopoverHeader: View {
    let status: String?
    var isLive = false
    var onDark = false
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if isLive {
                LiveDot(color: Theme.accentOnDark, size: 8, pulses: true)
            } else {
                AppMark(size: 18, color: onDark ? .white : Theme.ink)
                Text("Echoic").font(.display(16)).foregroundColor(onDark ? .white : Theme.ink)
            }
            if let status {
                Text(status)
                    .font(.inter(isLive ? 14 : 12, weight: isLive ? .semibold : .medium))
                    .foregroundColor(onDark ? .white : Theme.textMuted)
            }
            Spacer()
            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundColor(onDark ? Theme.darkTextMuted : Theme.textMuted)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

// MARK: - Ready

private struct ReadyPopover: View {
    @ObservedObject var coordinator: MeetingCoordinator
    @ObservedObject var meetingDetector: MeetingDetector
    let onSettings: () -> Void
    let onLibrary: () -> Void

    @AppStorage(MeetingCoordinator.meetingAudioSettingKey) private var meetingAudio = true
    @AppStorage(MeetingCoordinator.microphoneSettingKey) private var microphone = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverHeader(status: isOnCall ? nil : statusText, onSettings: onSettings)
            if let error = coordinator.state.errorText {
                ErrorNote(message: error).padding(.horizontal, 16).padding(.bottom, 12)
            }
            if isOnCall {
                OnCallStatus(text: CallPromptRouter.menuStatus(appName: meetingDetector.callAppName))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
            SourcePicker(meetingAudio: $meetingAudio, microphone: $microphone)
                .padding(.horizontal, 16)
            StartButton(
                title: isOnCall ? "Record this call" : "Start recording",
                isEnabled: canStart,
                onStart: isOnCall ? meetingDetector.acceptPrompt : coordinator.toggleRecording
            )
            .padding(.horizontal, 16)
            .padding(.top, 14)
            Text(startCaption)
                .font(.inter(12))
                .foregroundColor(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            PopoverMenu(onLibrary: onLibrary)
        }
        .background(Theme.surface)
        .environment(\.colorScheme, .light)
    }

    /// A call is detected and unanswered: the menu is in its on-a-call state.
    private var isOnCall: Bool { meetingDetector.isOnUnansweredCall && coordinator.state != .processing }

    private var canStart: Bool { (meetingAudio || microphone) && coordinator.state != .processing }

    private var statusText: String {
        switch coordinator.state {
        case .processing: return "Summarizing"
        case .error: return "Needs attention"
        default: return "Ready"
        }
    }

    private var startCaption: String {
        if coordinator.state == .processing { return "Summarizing the last meeting. You can record again when it's done." }
        if !meetingAudio && !microphone { return "Choose at least one source to start recording." }
        return "Audio stays on this Mac. Only the transcript text is sent for the summary."
    }
}

private struct SourcePicker: View {
    @Binding var meetingAudio: Bool
    @Binding var microphone: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupLabel("Listening to")
            Toggle(isOn: $meetingAudio) { SourceLabel(title: "Meeting audio", caption: "Everyone else on the call") }
            Toggle(isOn: $microphone) { SourceLabel(title: "My microphone", caption: "Default input, labelled as You") }
        }
        .toggleStyle(InkCheckboxStyle())
    }
}

private struct SourceLabel: View {
    let title: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.inter(13, weight: .medium)).foregroundColor(Theme.ink)
            Text(caption).font(.inter(12)).foregroundColor(Theme.textMuted)
        }
    }
}

/// "You're on a Zoom call" with the accent dot, above "Listening to".
private struct OnCallStatus: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Theme.accentFill).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(text)
                .font(.inter(15, weight: .semibold))
                .foregroundColor(Theme.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StartButton: View {
    let title: String
    let isEnabled: Bool
    let onStart: () -> Void

    var body: some View {
        Button(action: onStart) {
            HStack(spacing: 10) {
                LiveDot(size: 8)
                Text(title).font(.inter(14, weight: .semibold))
                Spacer()
                Text("⌘R").font(.mono(11)).foregroundColor(.white.opacity(0.7)).accessibilityHidden(true)
            }
        }
        .buttonStyle(InkButtonStyle(kind: .primary, height: 44, radius: Theme.Radius.card, fullWidth: true))
        .keyboardShortcut("r", modifiers: .command)
        .disabled(!isEnabled)
    }
}

private struct ErrorNote: View {
    let message: String
    var onDark = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundColor(onDark ? Theme.accentOnDark : Theme.accentText)
                .accessibilityHidden(true)
            Text(message)
                .font(.inter(12))
                .foregroundColor(onDark ? Theme.darkText2 : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PopoverMenu: View {
    let onLibrary: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MenuRow(title: "Open library", shortcut: "⌘L", action: onLibrary)
                .keyboardShortcut("l", modifiers: .command)
            MenuRow(title: "Quit Echoic", shortcut: "⌘Q") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
}

// MARK: - Recording

private struct RecordingPopover: View {
    @ObservedObject var coordinator: MeetingCoordinator
    let onSettings: () -> Void
    let onLiveTranscript: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverHeader(status: "Recording", isLive: true, onDark: true, onSettings: onSettings)
            HStack(alignment: .center) {
                RecordingTimer(startedAt: coordinator.currentMeeting?.startedAt)
                Spacer()
                WaveformMark()
            }
            .padding(.horizontal, 16)
            if let warning = coordinator.errorMessage {
                ErrorNote(message: warning, onDark: true).padding(.horizontal, 16).padding(.top, 8)
            }
            LiveTranscriptBox(segments: Array(coordinator.liveSegments.suffix(2)))
                .padding(.horizontal, 16)
                .padding(.top, 12)
            RecordingActions(bookmarkCount: coordinator.bookmarkCount,
                             onBookmark: coordinator.addBookmark,
                             onStop: coordinator.toggleRecording)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            Rectangle().fill(Theme.darkDivider).frame(height: 1)
            MenuRow(title: "Open live transcript", shortcut: "⌘T", onDark: true, action: onLiveTranscript)
                .keyboardShortcut("t", modifiers: .command)
                .padding(4)
        }
        .background(Theme.ink)
        .environment(\.colorScheme, .dark)
    }
}

/// Elapsed time, mono 44pt.
private struct RecordingTimer: View {
    let startedAt: Int64?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.format(elapsed(at: context.date)))
                .font(.mono(44, weight: .medium))
                .tracking(-1.3)
                .monospacedDigit()
                .foregroundColor(.white)
                .accessibilityLabel("Recording time \(Self.format(elapsed(at: context.date)))")
        }
    }

    private func elapsed(at date: Date) -> Int {
        guard let startedAt else { return 0 }
        return max(0, Int(date.timeIntervalSince1970 - Double(startedAt) / 1000))
    }

    static func format(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }
}

/// Static accent waveform beside the timer (decorative; the dot is the only animation).
private struct WaveformMark: View {
    private let heights: [CGFloat] = [10, 18, 28, 16, 24, 34, 20, 12, 22, 14]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, height in
                Capsule().fill(Theme.accentOnDark).frame(width: 3, height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Last two utterances; newest line white, the previous one dimmer.
private struct LiveTranscriptBox: View {
    let segments: [TranscriptSegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if segments.isEmpty {
                Text("Listening… the transcript appears here.")
                    .font(.inter(13))
                    .foregroundColor(Theme.darkTextMuted)
            }
            ForEach(Array(segments.enumerated()), id: \.element.startMs) { index, segment in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(speakerName(segment)) · \(Date.formatTimestamp(ms: segment.startMs))")
                        .font(.mono(11))
                        .foregroundColor(Theme.darkTextMuted)
                    Text(segment.text)
                        .font(.inter(13))
                        .foregroundColor(index == segments.count - 1 ? .white : Theme.darkText2)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).fill(Theme.darkSurface2))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live transcript")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func speakerName(_ segment: TranscriptSegment) -> String {
        if segment.isLocalSpeaker { return "You" }
        return segment.speakerId.map(SpeakerMerge.defaultLabel(for:)) ?? "Call"
    }
}

private struct RecordingActions: View {
    let bookmarkCount: Int
    let onBookmark: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBookmark) {
                Text(bookmarkCount == 0 ? "Bookmark" : "Bookmark · \(bookmarkCount)")
            }
            .buttonStyle(InkButtonStyle(kind: .secondary, onDark: true, height: 44, radius: Theme.Radius.card))
            .keyboardShortcut("b", modifiers: .command)
            .accessibilityLabel(bookmarkCount == 0 ? "Bookmark this moment" : "Bookmark this moment, \(bookmarkCount) so far")
            Button("Stop and summarize", action: onStop)
                .buttonStyle(InkButtonStyle(kind: .primary, onDark: true, height: 44, radius: Theme.Radius.card, fullWidth: true))
        }
    }
}

/// Elapsed recording time (used by the Live Transcript window).
struct RecordingDuration: View {
    let startedAt: Int64?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.format(startedAt: startedAt, now: context.date))
                .font(.caption.monospacedDigit())
                .foregroundColor(.red)
        }
    }

    static func format(startedAt: Int64?, now: Date) -> String {
        guard let startedAt else { return "00:00" }
        let seconds = max(0, Int(now.timeIntervalSince1970 - Double(startedAt) / 1000))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
