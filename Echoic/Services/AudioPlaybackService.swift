import Foundation
import AVFoundation
import Combine

/// Audio playback with scrubbing and transcript-segment-to-timestamp linking.
@MainActor
final class AudioPlaybackService: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    /// Loads an audio file for playback.
    func load(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        duration = player?.duration ?? 0
    }

    /// Starts or resumes playback.
    func play() {
        player?.play()
        isPlaying = true
        startTimer()
    }

    /// Pauses playback.
    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    /// Toggles play/pause.
    func togglePlayPause() {
        if isPlaying { pause() } else { play() }
    }

    /// Seeks to a specific time.
    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    /// Seeks to a transcript segment's timestamp.
    func seekToSegment(_ segment: TranscriptSegment) {
        let time = TimeInterval(segment.startMs) / 1000.0
        seek(to: time)
        if !isPlaying { play() }
    }

    /// Stops playback and releases resources.
    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        stopTimer()
    }

    /// Returns the segment currently being played, given a list of segments.
    func currentSegment(from segments: [TranscriptSegment]) -> TranscriptSegment? {
        let currentMs = Int64(currentTime * 1000)
        return segments.last { segment in
            segment.startMs <= currentMs && segment.endMs > currentMs
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.currentTime = self?.player?.currentTime ?? 0
                if self?.player?.isPlaying == false {
                    self?.isPlaying = false
                    self?.stopTimer()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
