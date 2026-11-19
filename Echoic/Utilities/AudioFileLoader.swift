import AVFoundation

enum AudioLoadError: Error {
    case unreadable(underlying: Error)
    case converterUnavailable
    case conversionFailed(underlying: Error?)
}

/// Decodes an audio file to 16 kHz mono Float32 samples for SpeakerKit and voice matching.
///
/// Replaces WhisperKit's `AudioProcessor.loadAudioAsFloatArray`, which loops forever when a
/// file's header claims more frames than it actually contains (a truncated or partially
/// written .m4a): its read loop waits for a frame position that never advances. This loader
/// reads sequentially and stops at the first empty read, so it always finishes.
enum AudioFileLoader {
    static let sampleRate: Double = 16_000
    /// 10 seconds at 48 kHz per read: small enough to keep peak memory low.
    private static let readFrames: AVAudioFrameCount = 480_000

    static func loadMono16k(from url: URL) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw AudioLoadError.unreadable(underlying: error)
        }

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false
        ),
            let converter = AVAudioConverter(from: file.processingFormat, to: outputFormat),
            let inputBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: readFrames)
        else {
            throw AudioLoadError.converterUnavailable
        }

        let ratio = sampleRate / file.processingFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(readFrames) * ratio) + 4096
        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(max(file.length, 0)) * ratio))

        var reachedEnd = false
        while !reachedEnd {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
                throw AudioLoadError.converterUnavailable
            }

            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
                // An error or an empty read both mean there's no more audio.
                guard (try? file.read(into: inputBuffer, frameCount: readFrames)) != nil,
                      inputBuffer.frameLength > 0 else {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return inputBuffer
            }

            if status == .error {
                throw AudioLoadError.conversionFailed(underlying: conversionError)
            }
            if let channel = outputBuffer.floatChannelData?[0], outputBuffer.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(outputBuffer.frameLength)))
            }
            reachedEnd = status == .endOfStream || (status == .inputRanDry && outputBuffer.frameLength == 0)
        }
        return samples
    }
}
