import AVFoundation
import XCTest
@testable import Echoic

final class AudioFileLoaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioFileLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Writes `seconds` of a 440 Hz tone as 48 kHz mono AAC, like the app's recordings.
    private func writeAAC(seconds: Double, name: String = "tone.m4a") throws -> URL {
        let url = directory.appendingPathComponent(name)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(seconds * 48_000)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames))
        buffer.frameLength = frames
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<Int(frames) {
            samples[index] = 0.3 * sinf(2 * .pi * 440 * Float(index) / 48_000)
        }
        try file.write(from: buffer)
        return url // file closes (and finalizes) when it goes out of scope
    }

    func test_loadMono16k_validAAC_returnsSixteenKilohertzSamples() throws {
        let url = try writeAAC(seconds: 3)

        let samples = try AudioFileLoader.loadMono16k(from: url)

        XCTAssertEqual(Double(samples.count), 3 * 16_000, accuracy: 16_000 * 0.1)
        XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.1)
    }

    /// The header still claims 3 s but only part of the audio data is present. WhisperKit's
    /// loader spins forever on this; ours must finish with the audio that exists.
    func test_loadMono16k_truncatedData_finishesWithPartialAudio() throws {
        let url = try writeAAC(seconds: 3)
        let data = try Data(contentsOf: url)
        try data.prefix(data.count / 2).write(to: url)

        let samples = (try? AudioFileLoader.loadMono16k(from: url)) ?? []

        XCTAssertLessThan(samples.count, 3 * 16_000)
    }

    func test_loadMono16k_headerOnlyFile_throws() throws {
        let url = try writeAAC(seconds: 1)
        try Data(contentsOf: url).prefix(40).write(to: url)

        XCTAssertThrowsError(try AudioFileLoader.loadMono16k(from: url))
    }

    func test_isReadableAudio_validVersusHeaderOnlyVersusMissing() throws {
        let valid = try writeAAC(seconds: 1, name: "valid.m4a")
        let broken = try writeAAC(seconds: 1, name: "broken.m4a")
        try Data(contentsOf: broken).prefix(40).write(to: broken)

        XCTAssertTrue(AudioFileManager.isReadableAudio(at: valid))
        XCTAssertFalse(AudioFileManager.isReadableAudio(at: broken))
        XCTAssertFalse(AudioFileManager.isReadableAudio(at: directory.appendingPathComponent("missing.m4a")))
    }

    func test_concatenateSegments_writesCompleteFileAndLeavesNoPartial() async throws {
        let first = try writeAAC(seconds: 1, name: "segment_0001.m4a")
        let second = try writeAAC(seconds: 1, name: "segment_0002.m4a")
        let output = directory.appendingPathComponent("audio.m4a")

        try await AudioFileManager.concatenateSegments([first, second], to: output)

        XCTAssertTrue(AudioFileManager.isReadableAudio(at: output))
        let samples = try AudioFileLoader.loadMono16k(from: output)
        XCTAssertEqual(Double(samples.count), 2 * 16_000, accuracy: 16_000 * 0.2)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains("partial") }
        XCTAssertTrue(leftovers.isEmpty)
    }
}
