import XCTest
@testable import Echoic

/// Tests that the ring buffer correctly preserves samples for
/// the transcription pipeline — verifying the fix where the
/// SCStreamOutput handler was consuming samples before transcription.
final class RingBufferTranscriptionTests: XCTestCase {

    /// Simulates the fixed audio pipeline: writeDownsampled feeds the buffer,
    /// and the transcription loop can still read the samples.
    func testWriteDownsampledDoesNotConsumeForTranscription() {
        let buffer = RingBuffer(durationSeconds: 1, sourceSampleRate: 16000, targetSampleRate: 16000)

        // Simulate what the fixed SCStreamOutput handler does:
        // write downsampled samples directly (no read to drain for encoder)
        let samples: [Float] = Array(repeating: 0.5, count: 1600) // 100ms at 16kHz
        buffer.writeDownsampled(samples)

        // Transcription loop should see all samples
        XCTAssertEqual(buffer.count, 1600)

        // Simulate another batch arriving
        let samples2: [Float] = Array(repeating: 0.3, count: 1600)
        buffer.writeDownsampled(samples2)

        // Both batches should be available
        XCTAssertEqual(buffer.count, 3200)

        // Transcription loop reads a chunk
        let chunk = buffer.read(count: 1600)
        XCTAssertEqual(chunk.count, 1600)
        XCTAssertEqual(chunk[0], 0.5, accuracy: 0.001)

        // Second batch still available
        XCTAssertEqual(buffer.count, 1600)
        let chunk2 = buffer.read(count: 1600)
        XCTAssertEqual(chunk2[0], 0.3, accuracy: 0.001)
    }

    /// Verifies the manual downsampling logic matches the ring buffer's built-in downsampling.
    func testManualDownsampleMatchesRingBuffer() {
        // Simulate 48kHz input: 30 samples → 10 at 16kHz
        let input48k: [Float] = (0..<30).map { Float($0) }
        let downsampleFactor = 3

        // Manual downsampling (as done in the fixed SCStreamOutput)
        let downsampledCount = input48k.count / downsampleFactor
        var manual = [Float](repeating: 0, count: downsampledCount)
        for i in 0..<downsampledCount {
            let start = i * downsampleFactor
            let end = min(start + downsampleFactor, input48k.count)
            var sum: Float = 0
            for j in start..<end {
                sum += input48k[j]
            }
            manual[i] = sum / Float(end - start)
        }

        // Ring buffer's built-in downsampling
        let buffer = RingBuffer(durationSeconds: 1, sourceSampleRate: 48000, targetSampleRate: 16000)
        buffer.write(input48k)
        let fromBuffer = buffer.read(count: downsampledCount)

        XCTAssertEqual(manual.count, fromBuffer.count)
        for i in 0..<manual.count {
            XCTAssertEqual(manual[i], fromBuffer[i], accuracy: 0.001,
                           "Sample \(i) mismatch: manual=\(manual[i]) buffer=\(fromBuffer[i])")
        }
    }

    /// Ensures samples smaller than the downsample factor are ignored (no partial samples).
    func testDownsampleIgnoresPartialSamples() {
        let downsampleFactor = 3
        // 2 samples at 48kHz < downsampleFactor, should produce 0 downsampled samples
        let input: [Float] = [1.0, 2.0]
        let downsampledCount = input.count / downsampleFactor
        XCTAssertEqual(downsampledCount, 0)
    }

    /// Verifies concurrent writes (simulating SCStreamOutput) and reads (simulating transcription loop)
    /// don't lose data or crash.
    func testConcurrentWriteAndTranscriptionRead() {
        let buffer = RingBuffer(durationSeconds: 2, sourceSampleRate: 16000, targetSampleRate: 16000)
        let writeExpectation = XCTestExpectation(description: "Writes complete")
        let readExpectation = XCTestExpectation(description: "Reads complete")

        let totalWriteSamples = 16000 // 1 second
        let batchSize = 160 // 10ms batches (typical audio callback size)
        var totalRead = 0

        // Writer thread (simulates SCStreamOutput callback)
        DispatchQueue.global(qos: .userInitiated).async {
            var written = 0
            while written < totalWriteSamples {
                let batch = [Float](repeating: 1.0, count: batchSize)
                buffer.writeDownsampled(batch)
                written += batchSize
            }
            writeExpectation.fulfill()
        }

        // Reader thread (simulates transcription loop)
        DispatchQueue.global(qos: .default).async {
            while totalRead < totalWriteSamples {
                let available = buffer.count
                if available >= batchSize {
                    let chunk = buffer.read(count: batchSize)
                    totalRead += chunk.count
                } else {
                    usleep(1000) // 1ms
                }
            }
            readExpectation.fulfill()
        }

        wait(for: [writeExpectation, readExpectation], timeout: 5.0)
        XCTAssertEqual(totalRead, totalWriteSamples)
    }
}
