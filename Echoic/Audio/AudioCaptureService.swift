import Foundation
import ScreenCaptureKit
import AVFoundation
import os.log

private let captureLogger = Logger(subsystem: "com.echoic.app", category: "AudioCapture")

/// Captures system audio via ScreenCaptureKit.
/// Critical Rule #6: Screen Recording permission is for audio capture only.
final class AudioCaptureService: NSObject {
    private var stream: SCStream?
    private(set) var isCapturing = false

    /// Ring buffer for transcription pipeline (48→16 kHz downsampled).
    let ringBuffer = RingBuffer(durationSeconds: 30, sourceSampleRate: 48000, targetSampleRate: 16000)

    /// AAC encoder for writing segments to disk.
    private var encoder: AACEncoder?

    /// Callback for raw audio samples (at 48 kHz, for monitoring/level meters).
    var onAudioSamples: (([Float]) -> Void)?

    /// The meeting ID currently being recorded.
    private(set) var currentMeetingId: String?

    /// Starts capturing system audio for a meeting.
    func startCapture(meetingId: String) async throws {
        guard !isCapturing else { return }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplayFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true // Critical: prevent feedback loops
        config.sampleRate = 48000
        config.channelCount = 1

        // We only want audio — minimize video overhead
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        // Set up AAC encoder for segment writing (48kHz to match capture)
        let segmentsDir = try AudioFileManager.segmentsDirectory(meetingId: meetingId)
        let enc = AACEncoder(outputDirectory: segmentsDir, sampleRate: 48000)
        try enc.start()
        self.encoder = enc
        self.currentMeetingId = meetingId

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))

        try await stream.startCapture()

        self.stream = stream
        isCapturing = true
    }

    /// Stops capturing system audio and finalizes the recording.
    func stopCapture() async throws {
        guard isCapturing, let stream else { return }

        try await stream.stopCapture()
        self.stream = nil
        isCapturing = false

        // Finalize encoder
        try await encoder?.finish()

        // Concatenate segments into final file
        if let meetingId = currentMeetingId, let encoder {
            captureLogger.info("Encoder has \(encoder.completedSegments.count) segments to concatenate")
            if encoder.completedSegments.isEmpty {
                captureLogger.warning("No segments to concatenate — audio file will not be created")
            } else {
                let outputURL = try AudioFileManager.finalAudioURL(meetingId: meetingId)
                try await AudioFileManager.concatenateSegments(encoder.completedSegments, to: outputURL)
                captureLogger.info("Audio concatenated to \(outputURL.path)")
                try AudioFileManager.cleanupSegments(meetingId: meetingId)
            }
        }

        encoder = nil
        currentMeetingId = nil
        ringBuffer.reset()
    }

    /// Checks if Screen Recording permission is granted.
    static func hasScreenCapturePermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Requests Screen Recording permission.
    static func requestScreenCapturePermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}

// MARK: - SCStreamOutput

extension AudioCaptureService: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        // Extract PCM samples from the buffer
        guard let dataBuffer = sampleBuffer.dataBuffer else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let pointer = dataPointer, length > 0 else { return }

        let floatCount = length / MemoryLayout<Float>.size
        let floatPointer = UnsafeRawPointer(pointer).bindMemory(to: Float.self, capacity: floatCount)
        let samples = Array(UnsafeBufferPointer(start: floatPointer, count: floatCount))

        // Downsample 48→16 kHz for both ring buffer and encoder
        let downsampleFactor = 3 // 48000 / 16000
        let downsampledCount = samples.count / downsampleFactor
        guard downsampledCount > 0 else { return }

        var downsampled = [Float](repeating: 0, count: downsampledCount)
        for i in 0..<downsampledCount {
            let start = i * downsampleFactor
            let end = min(start + downsampleFactor, samples.count)
            var sum: Float = 0
            for j in start..<end {
                sum += samples[j]
            }
            downsampled[i] = sum / Float(end - start)
        }

        // Feed into ring buffer for transcription (16kHz downsampled)
        ringBuffer.writeDownsampled(downsampled)

        // Feed raw 48kHz audio into AAC encoder
        try? encoder?.encode(samples: samples)

        // Notify listeners
        onAudioSamples?(samples)
    }
}

// MARK: - Errors

enum AudioCaptureError: Error, LocalizedError {
    case noDisplayFound
    case captureAlreadyRunning
    case permissionDenied
    case permissionNotGranted

    var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "No display found for audio capture."
        case .captureAlreadyRunning:
            return "Audio capture is already running."
        case .permissionDenied:
            return "Screen Recording permission was denied."
        case .permissionNotGranted:
            return "Screen Recording permission is required. Open System Settings → Privacy & Security → Screen Recording, and enable Echoic."
        }
    }
}
