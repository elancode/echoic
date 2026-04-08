import Foundation
import Accelerate
import AVFoundation

/// Thread-safe PCM ring buffer with 48→16 kHz downsampling.
/// Holds up to 30 seconds of audio at 16 kHz mono (480,000 samples).
final class RingBuffer: @unchecked Sendable {
    private let capacity: Int
    private var buffer: [Float]
    private var writeIndex: Int = 0
    private var readIndex: Int = 0
    private var availableSamples: Int = 0
    private let lock = NSLock()

    /// Source and target sample rates for downsampling.
    private let sourceSampleRate: Double
    private let targetSampleRate: Double
    private let downsampleFactor: Int

    /// Creates a ring buffer.
    /// - Parameters:
    ///   - durationSeconds: Buffer duration in seconds (default 30).
    ///   - sourceSampleRate: Input sample rate (default 48000).
    ///   - targetSampleRate: Output sample rate (default 16000).
    init(durationSeconds: Int = 30, sourceSampleRate: Double = 48000, targetSampleRate: Double = 16000) {
        self.sourceSampleRate = sourceSampleRate
        self.targetSampleRate = targetSampleRate
        self.downsampleFactor = Int(sourceSampleRate / targetSampleRate)
        self.capacity = durationSeconds * Int(targetSampleRate)
        self.buffer = [Float](repeating: 0, count: capacity)
    }

    /// Writes audio samples to the buffer, downsampling from source to target rate.
    /// - Parameter samples: PCM float samples at the source sample rate.
    func write(_ samples: [Float]) {
        // Downsample using simple decimation with anti-alias averaging
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

        writeDownsampled(downsampled)
    }

    /// Writes already-downsampled (16 kHz) samples directly.
    func writeDownsampled(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }

        for sample in samples {
            buffer[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity

            if availableSamples < capacity {
                availableSamples += 1
            } else {
                // Buffer full — advance read index (overwrite oldest)
                readIndex = (readIndex + 1) % capacity
            }
        }
    }

    /// Reads up to `count` samples from the buffer.
    /// - Parameter count: Maximum number of samples to read.
    /// - Returns: Array of PCM float samples at the target sample rate.
    func read(count: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        let toRead = min(count, availableSamples)
        guard toRead > 0 else { return [] }

        var result = [Float](repeating: 0, count: toRead)

        for i in 0..<toRead {
            result[i] = buffer[readIndex]
            readIndex = (readIndex + 1) % capacity
        }

        availableSamples -= toRead
        return result
    }

    /// Reads all available samples without consuming them (peek).
    func peek() -> [Float] {
        lock.lock()
        defer { lock.unlock() }

        guard availableSamples > 0 else { return [] }

        var result = [Float](repeating: 0, count: availableSamples)
        var index = readIndex

        for i in 0..<availableSamples {
            result[i] = buffer[index]
            index = (index + 1) % capacity
        }

        return result
    }

    /// Number of samples currently available for reading.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return availableSamples
    }

    /// Resets the buffer to empty.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        writeIndex = 0
        readIndex = 0
        availableSamples = 0
    }
}
