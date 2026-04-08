import XCTest
@testable import Echoic

final class RingBufferTests: XCTestCase {
    func testWriteAndRead() {
        let buffer = RingBuffer(durationSeconds: 1, sourceSampleRate: 16000, targetSampleRate: 16000)
        let samples: [Float] = [1.0, 2.0, 3.0, 4.0, 5.0]

        buffer.writeDownsampled(samples)
        XCTAssertEqual(buffer.count, 5)

        let result = buffer.read(count: 5)
        XCTAssertEqual(result, samples)
        XCTAssertEqual(buffer.count, 0)
    }

    func testDownsampling() {
        // 48kHz → 16kHz = 3x decimation
        let buffer = RingBuffer(durationSeconds: 1, sourceSampleRate: 48000, targetSampleRate: 16000)

        // 30 samples at 48kHz → 10 samples at 16kHz
        let samples = [Float](repeating: 1.0, count: 30)
        buffer.write(samples)

        XCTAssertEqual(buffer.count, 10)

        let result = buffer.read(count: 10)
        XCTAssertEqual(result.count, 10)
        // Each downsampled value should be average of 3 consecutive 1.0 values = 1.0
        for sample in result {
            XCTAssertEqual(sample, 1.0, accuracy: 0.001)
        }
    }

    func testOverflow() {
        // 1 second at 16kHz = 16000 samples capacity
        let buffer = RingBuffer(durationSeconds: 1, sourceSampleRate: 16000, targetSampleRate: 16000)

        // Write more than capacity
        let samples = [Float](repeating: 1.0, count: 20000)
        buffer.writeDownsampled(samples)

        // Should only hold 16000
        XCTAssertEqual(buffer.count, 16000)
    }

    func testReset() {
        let buffer = RingBuffer(durationSeconds: 1, sourceSampleRate: 16000, targetSampleRate: 16000)
        buffer.writeDownsampled([1.0, 2.0, 3.0])
        XCTAssertEqual(buffer.count, 3)

        buffer.reset()
        XCTAssertEqual(buffer.count, 0)
    }

    func testPeek() {
        let buffer = RingBuffer(durationSeconds: 1, sourceSampleRate: 16000, targetSampleRate: 16000)
        let samples: [Float] = [1.0, 2.0, 3.0]
        buffer.writeDownsampled(samples)

        let peeked = buffer.peek()
        XCTAssertEqual(peeked, samples)
        // Peek should not consume
        XCTAssertEqual(buffer.count, 3)
    }

    func testThreadSafety() {
        let buffer = RingBuffer(durationSeconds: 1, sourceSampleRate: 16000, targetSampleRate: 16000)
        let expectation = XCTestExpectation(description: "Concurrent access")
        expectation.expectedFulfillmentCount = 2

        DispatchQueue.global().async {
            for _ in 0..<1000 {
                buffer.writeDownsampled([Float.random(in: -1...1)])
            }
            expectation.fulfill()
        }

        DispatchQueue.global().async {
            for _ in 0..<1000 {
                _ = buffer.read(count: 1)
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }
}
