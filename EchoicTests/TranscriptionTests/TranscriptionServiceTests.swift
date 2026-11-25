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

    // MARK: - Run lifecycle

    private func makeSource() -> TranscriptionService.AudioSource {
        TranscriptionService.AudioSource(
            ringBuffer: RingBuffer(durationSeconds: 30, sourceSampleRate: 16000, targetSampleRate: 16000)
        )
    }

    /// Waits up to `timeout` for `condition`, polling every 20 ms.
    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    func test_startTranscription_singleStart_runsOneLoop() {
        let service = TranscriptionService()
        service.startTranscription(meetingId: "A", sources: [makeSource()])
        defer { service.stopTranscription() }

        waitUntil { service.activeLoopCount == 1 }
        XCTAssertEqual(service.activeLoopCount, 1)
        XCTAssertEqual(service.meetingId, "A")
    }

    func test_stopTranscription_afterStart_endsLoop() {
        let service = TranscriptionService()
        service.startTranscription(meetingId: "A", sources: [makeSource()])
        waitUntil { service.activeLoopCount == 1 }

        service.stopTranscription()

        waitUntil { service.activeLoopCount == 0 }
        XCTAssertEqual(service.activeLoopCount, 0)
        XCTAssertFalse(service.active)
        XCTAssertNil(service.meetingId)
    }

    /// Stop followed immediately by start (a quick re-record) must not leave the
    /// previous run's loop alive alongside the new one.
    func test_startTranscription_immediatelyAfterStop_previousLoopExits() {
        let service = TranscriptionService()
        service.startTranscription(meetingId: "A", sources: [makeSource()])
        waitUntil { service.activeLoopCount == 1 }

        service.stopTranscription()
        service.startTranscription(meetingId: "B", sources: [makeSource()])
        defer { service.stopTranscription() }

        // Give the old loop time to wake from its 100 ms poll.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(service.activeLoopCount, 1)
        XCTAssertEqual(service.meetingId, "B")
    }

    /// Start, stop and state reads from many threads at once must be safe.
    func test_startStopTranscription_concurrentCalls_areThreadSafe() {
        let service = TranscriptionService()
        DispatchQueue.concurrentPerform(iterations: 2_000) { index in
            switch index % 4 {
            case 0: service.startTranscription(meetingId: "m\(index)", sources: [makeSource()])
            case 1: service.stopTranscription()
            case 2: _ = service.meetingId
            default: service.onSegment = { _ in }
            }
        }
        service.stopTranscription()
        waitUntil { service.activeLoopCount == 0 }
        XCTAssertEqual(service.activeLoopCount, 0)
    }
}
