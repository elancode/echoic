import Foundation
import AVFoundation
import AudioToolbox

/// Encodes PCM audio to AAC and writes 30-second segments to disk.
/// Critical Rule #8: Segments flushed every 30 seconds — crash loses at most 30s.
final class AACEncoder {
    private let outputDirectory: URL
    private let sampleRate: Double
    private let segmentDuration: TimeInterval = 30.0
    private var segmentIndex: Int = 0
    private var currentWriter: AVAssetWriter?
    private var currentInput: AVAssetWriterInput?
    private var samplesInSegment: Int = 0
    private let samplesPerSegment: Int
    private var segmentPaths: [URL] = []

    enum AACEncoderError: Error {
        case writerCreationFailed
        case encodingFailed
        case invalidState
    }

    /// Creates an encoder that writes segments to the given directory.
    /// - Parameters:
    ///   - outputDirectory: Directory to write .m4a segment files.
    ///   - sampleRate: Input sample rate (default 16000 for WhisperKit-ready audio).
    init(outputDirectory: URL, sampleRate: Double = 16000) {
        self.outputDirectory = outputDirectory
        self.sampleRate = sampleRate
        self.samplesPerSegment = Int(sampleRate * segmentDuration)
    }

    /// Starts encoding. Creates the output directory and the first segment.
    func start() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        segmentIndex = 0
        segmentPaths = []
        try startNewSegment()
    }

    /// Encodes PCM samples. Automatically rolls to a new segment every 30 seconds.
    func encode(samples: [Float]) throws {
        guard let writer = currentWriter, let input = currentInput else {
            throw AACEncoderError.invalidState
        }

        // Convert Float array to CMSampleBuffer
        let sampleBuffer = try createSampleBuffer(from: samples)

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }

        samplesInSegment += samples.count

        // Roll to new segment every 30 seconds
        if samplesInSegment >= samplesPerSegment {
            try finishCurrentSegment()
            try startNewSegment()
        }
    }

    /// Finishes encoding. Closes the current segment.
    func finish() async throws {
        try finishCurrentSegment()
    }

    /// Returns the paths of all completed segment files.
    var completedSegments: [URL] {
        segmentPaths
    }

    // MARK: - Private

    private func startNewSegment() throws {
        let fileName = String(format: "segment_%04d.m4a", segmentIndex)
        let segmentURL = outputDirectory.appendingPathComponent(fileName)

        let writer = try AVAssetWriter(outputURL: segmentURL, fileType: .m4a)

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000
        ]

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = true

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        currentWriter = writer
        currentInput = input
        samplesInSegment = 0
    }

    private func finishCurrentSegment() throws {
        guard let writer = currentWriter, let input = currentInput else { return }

        input.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        if writer.status == .completed {
            segmentPaths.append(writer.outputURL)
        }

        currentWriter = nil
        currentInput = nil
        segmentIndex += 1
    }

    private func createSampleBuffer(from samples: [Float]) throws -> CMSampleBuffer {
        let frameCount = samples.count
        let bytesPerFrame = MemoryLayout<Float>.size

        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: UInt32(bytesPerFrame),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(bytesPerFrame),
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        var formatDescription: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        guard status == noErr, let format = formatDescription else {
            throw AACEncoderError.encodingFailed
        }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(sampleRate)),
            presentationTimeStamp: CMTime(value: Int64(samplesInSegment), timescale: Int32(sampleRate)),
            decodeTimeStamp: .invalid
        )

        let dataSize = frameCount * bytesPerFrame

        var blockBuffer: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard let block = blockBuffer else {
            throw AACEncoderError.encodingFailed
        }

        samples.withUnsafeBufferPointer { ptr in
            CMBlockBufferReplaceDataBytes(
                with: ptr.baseAddress!,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: dataSize
            )
        }

        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: frameCount,
            presentationTimeStamp: timing.presentationTimeStamp,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard let buffer = sampleBuffer else {
            throw AACEncoderError.encodingFailed
        }

        return buffer
    }
}
