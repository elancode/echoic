import XCTest
@testable import Echoic

final class TranscriptionServiceTests: XCTestCase {
    func test_isSilent_emptySamples_returnsTrue() {
        XCTAssertTrue(TranscriptionService.isSilent([], threshold: 0.005))
    }

    func test_isSilent_lowNoiseFloor_returnsTrue() {
        let samples = (0..<16_000).map { _ in Float.random(in: -0.001...0.001) }

        XCTAssertTrue(TranscriptionService.isSilent(samples, threshold: 0.005))
    }

    func test_isSilent_speechLevelSignal_returnsFalse() {
        let samples = (0..<16_000).map { Float(sin(Double($0) * 0.05) * 0.1) }

        XCTAssertFalse(TranscriptionService.isSilent(samples, threshold: 0.005))
    }
}
