import XCTest
import AVFoundation
@testable import Echoic

final class MicrophoneResamplerTests: XCTestCase {
    private func sineBuffer(sampleRate: Double, channels: AVAudioChannelCount = 1, seconds: Double = 1) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels))
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            let data = try XCTUnwrap(buffer.floatChannelData?[channel])
            for i in 0..<Int(frames) {
                data[i] = Float(sin(2 * Double.pi * 440 * Double(i) / sampleRate) * 0.3)
            }
        }
        return buffer
    }

    /// Feeds audio in 100ms chunks, as a mic tap would. The converter has a small
    /// fixed startup latency (~14ms), so counts are checked over 10s where it's negligible.
    private func resample(sampleRate: Double, channels: AVAudioChannelCount = 1, seconds: Double = 10) throws -> [Float] {
        let input = try sineBuffer(sampleRate: sampleRate, channels: channels, seconds: seconds)
        let resampler = try XCTUnwrap(MicrophoneResampler(inputFormat: input.format))
        let chunk = AVAudioFrameCount(sampleRate / 10)
        var output: [Float] = []
        var offset: AVAudioFrameCount = 0
        while offset < input.frameLength {
            let slice = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: chunk))
            slice.frameLength = min(chunk, input.frameLength - offset)
            for channel in 0..<Int(channels) {
                let src = try XCTUnwrap(input.floatChannelData?[channel]).advanced(by: Int(offset))
                try XCTUnwrap(slice.floatChannelData?[channel]).update(from: src, count: Int(slice.frameLength))
            }
            output += resampler.resample(slice)
            offset += slice.frameLength
        }
        return output
    }

    func test_resample_48kHz_produces16kHzSampleCount() throws {
        XCTAssertEqual(Double(try resample(sampleRate: 48_000).count), 160_000, accuracy: 50)
    }

    func test_resample_24kHzAirPodsRate_produces16kHzSampleCount() throws {
        XCTAssertEqual(Double(try resample(sampleRate: 24_000).count), 160_000, accuracy: 50)
    }

    func test_resample_44_1kHz_produces16kHzSampleCount() throws {
        XCTAssertEqual(Double(try resample(sampleRate: 44_100).count), 160_000, accuracy: 50)
    }

    func test_resample_stereoInput_producesMonoAt16kHz() throws {
        XCTAssertEqual(Double(try resample(sampleRate: 48_000, channels: 2).count), 160_000, accuracy: 50)
    }

    func test_resample_preservesSignalLevel() throws {
        let output = try resample(sampleRate: 24_000)
        let rms = sqrt(output.map { $0 * $0 }.reduce(0, +) / Float(output.count))

        XCTAssertEqual(rms, 0.3 / sqrt(2), accuracy: 0.03)
    }
}
