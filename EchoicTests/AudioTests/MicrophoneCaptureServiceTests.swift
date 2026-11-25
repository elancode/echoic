import AVFoundation
import XCTest
@testable import Echoic

final class MicrophoneCaptureServiceTests: XCTestCase {
    private func format(_ sampleRate: Double, channels: AVAudioChannelCount = 1) throws -> AVAudioFormat {
        try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels))
    }

    func test_tapFormat_matchingHardware_returnsFormat() throws {
        let hardware = try format(48_000)

        let tap = MicrophoneCaptureService.tapFormat(hardware: hardware, output: try format(48_000))

        XCTAssertEqual(tap?.sampleRate, 48_000)
        XCTAssertEqual(tap?.channelCount, 1)
    }

    /// A Bluetooth headset switching to call mode drops the hardware to 24 kHz
    /// while the engine's cached output format still says 48 kHz. Installing a
    /// tap with the stale format raises an Objective-C exception, which Swift
    /// can't catch — so this mismatch must be rejected before `installTap`.
    func test_tapFormat_staleOutputSampleRate_returnsNil() throws {
        let tap = MicrophoneCaptureService.tapFormat(hardware: try format(24_000), output: try format(48_000))

        XCTAssertNil(tap)
    }

    func test_tapFormat_channelMismatch_returnsNil() throws {
        let tap = MicrophoneCaptureService.tapFormat(hardware: try format(48_000, channels: 2), output: try format(48_000))

        XCTAssertNil(tap)
    }

    func test_tapFormat_noHardwareInput_returnsNil() throws {
        let empty = AVAudioFormat()

        XCTAssertNil(MicrophoneCaptureService.tapFormat(hardware: empty, output: empty))
    }
}
