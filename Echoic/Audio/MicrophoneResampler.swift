import AVFoundation
import os.log

private let resamplerLogger = Logger(subsystem: "com.echoic.app", category: "MicResampler")

/// Converts microphone buffers at any device rate/channel count (48 kHz built-in,
/// 24 kHz or 16 kHz Bluetooth headsets, 44.1 kHz USB) to 16 kHz mono for WhisperKit.
/// Stateful: reuse one instance per capture session. Not thread-safe — call from
/// the audio tap only.
final class MicrophoneResampler {
    static let targetSampleRate: Double = 16_000

    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat
    private let ratio: Double

    init?(inputFormat: AVAudioFormat) {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            return nil
        }
        self.converter = converter
        self.outputFormat = outputFormat
        self.ratio = Self.targetSampleRate / inputFormat.sampleRate
    }

    /// Returns 16 kHz mono samples for the given input buffer.
    func resample(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return [] }

        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                // Keep converter state for the next tap buffer instead of flushing
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, let data = output.floatChannelData?[0] else {
            resamplerLogger.error("Mic resample failed: \(error?.localizedDescription ?? "unknown error")")
            return []
        }
        return Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
    }
}
