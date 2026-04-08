import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject private var coordinator = MeetingCoordinator.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Echoic")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "gear")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if case .error(let message) = coordinator.state {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)

                Divider()
            }

            // Source picker (only when not recording)
            if coordinator.state != .recording {
                Picker("", selection: $coordinator.recordingMode) {
                    ForEach(RecordingMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 2)
            }

            // Record button
            Button(action: toggleRecording) {
                HStack(spacing: 8) {
                    Image(systemName: coordinator.state == .recording ? "stop.circle.fill" : "record.circle")
                        .foregroundColor(coordinator.state == .recording ? .red : .primary)
                        .font(.system(size: 16))
                    Text(coordinator.state == .recording ? "Stop Recording" : "Start Recording")
                        .font(.system(size: 13))
                    Spacer()
                    if coordinator.state == .recording {
                        RecordingDuration(startedAt: coordinator.currentMeeting?.startedAt)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(coordinator.state == .processing)

            // Live transcript preview during recording
            if coordinator.state == .recording && !coordinator.liveSegments.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(coordinator.liveSegments.suffix(3), id: \.startMs) { segment in
                        Text(segment.text)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }

            Divider()

            Button(action: openLibrary) {
                HStack(spacing: 8) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 12))
                    Text("Open Library")
                        .font(.system(size: 13))
                    Spacer()
                    Text("\u{2318}L")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()

            Button(action: { NSApp.terminate(nil) }) {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                    Text("Quit Echoic")
                        .font(.system(size: 13))
                    Spacer()
                    Text("\u{2318}Q")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 260)
    }

    private func toggleRecording() {
        // Assign databaseWriter before entering the Task to avoid
        // mutating @Published state during a view update cycle.
        if coordinator.state != .recording {
            coordinator.databaseWriter = DatabaseManager.shared.databaseWriter
        }
        Task { @MainActor in
            if coordinator.state == .recording {
                await coordinator.stopRecording()
            } else {
                await coordinator.startRecording()
            }
        }
    }

    private func openSettings() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openLibrary() {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: "library")
        NSApp.activate(ignoringOtherApps: true)
    }

}

struct StatusBadge: View {
    let status: Meeting.Status

    var body: some View {
        Text(status.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(.white)
            .clipShape(Capsule())
    }

    private var backgroundColor: Color {
        switch status {
        case .recording: return .red
        case .processing: return .orange
        case .ready: return .green
        case .error: return .gray
        }
    }
}

struct RecordingDuration: View {
    let startedAt: Int64?
    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formatDuration(elapsed))
            .font(.caption.monospacedDigit())
            .foregroundColor(.red)
            .onReceive(timer) { _ in
                guard let start = startedAt else { return }
                elapsed = Date().timeIntervalSince1970 - Double(start) / 1000
            }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
