import SwiftUI

/// Scrollable view of the in-progress meeting transcript.
/// Follows new segments automatically unless the user turns auto-scroll off.
struct LiveTranscriptView: View {
    @ObservedObject private var coordinator = MeetingCoordinator.shared
    @State private var autoScroll = true

    var body: some View {
        VStack(spacing: 0) {
            LiveTranscriptHeader(
                state: coordinator.state,
                startedAt: coordinator.currentMeeting?.startedAt,
                autoScroll: $autoScroll
            )
            Divider()
            if coordinator.liveSegments.isEmpty {
                LiveTranscriptEmptyState(state: coordinator.state)
            } else {
                LiveTranscriptList(segments: coordinator.liveSegments, autoScroll: autoScroll)
            }
        }
        .frame(minWidth: 360, minHeight: 300)
    }
}

// MARK: - Header

private struct LiveTranscriptHeader: View {
    let state: MeetingState
    let startedAt: Int64?
    @Binding var autoScroll: Bool

    var body: some View {
        HStack(spacing: 8) {
            status
            Spacer()
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .accessibilityLabel("Auto-scroll to newest transcript line")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var status: some View {
        switch state {
        case .recording:
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text("Recording")
                .font(.system(size: 12, weight: .medium))
            RecordingDuration(startedAt: startedAt)
        case .processing:
            ProgressView()
                .controlSize(.small)
            Text("Processing meeting…")
                .font(.system(size: 12, weight: .medium))
        case .idle, .error:
            Text("No meeting in progress")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Empty State

private struct LiveTranscriptEmptyState: View {
    let state: MeetingState

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var message: String {
        switch state {
        case .recording:
            return "Listening… the transcript will appear here\nas people speak."
        case .processing:
            return "No live transcript was captured."
        case .idle, .error:
            return "Start a recording to see the live transcript."
        }
    }
}

// MARK: - Transcript List

private struct LiveTranscriptList: View {
    let segments: [TranscriptSegment]
    let autoScroll: Bool

    private let bottomAnchorId = "live-transcript-bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    // Segments are append-only during a recording, so the offset is a stable ID.
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        LiveTranscriptRow(segment: segment)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorId)
                }
                .padding(14)
                .textSelection(.enabled)
            }
            .onAppear {
                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
            }
            .onChange(of: segments.count) { _ in
                guard autoScroll else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                }
            }
            .onChange(of: autoScroll) { enabled in
                guard enabled else { return }
                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
            }
        }
    }
}

private struct LiveTranscriptRow: View {
    let segment: TranscriptSegment

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Date.formatTimestamp(ms: segment.startMs))
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.secondary)
            Text(segment.text)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
