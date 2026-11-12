import Foundation
import os.log
import WhisperKit

private let logger = Logger(subsystem: "com.echoic.app", category: "Transcription")

/// Manages real-time transcription using WhisperKit.
/// Processes 10-second chunks with 2-second overlap, deduplicates by timestamp.
/// Critical Rule #2: Runs in-process, no sidecars.
final class TranscriptionService {
    private var isTranscribing = false
    private var whisperKit: WhisperKit?
    private let chunkDuration: TimeInterval = 10.0
    private let overlapDuration: TimeInterval = 2.0
    private let sampleRate: Double = 16000

    /// Callback for new transcript segments.
    var onSegment: ((TranscriptSegment) -> Void)?

    /// Current meeting ID being transcribed.
    private(set) var meetingId: String?

    /// Folder of the currently loaded model (nil if none, or loaded by variant name).
    private(set) var loadedModelFolder: String?

    /// Whether a WhisperKit model is loaded and ready.
    var isModelLoaded: Bool { whisperKit != nil }

    /// Initializes WhisperKit with the given model variant.
    /// - Parameter model: Model name (e.g. "small.en", "large-v3"). If nil, uses default.
    /// No-op if a model is already loaded.
    func initialize(model: String? = nil) async throws {
        guard whisperKit == nil else { return }

        let manager = ModelDownloadManager()
        manager.cleanCache()

        // Ensure tokenizer files exist for all downloaded models
        if let modelPath = manager.bestAvailableModelPath() {
            await manager.ensureTokenizerFiles(in: URL(fileURLWithPath: modelPath))
        }

        let baseDir = manager.baseDirectory
        let config = WhisperKitConfig(
            model: model,
            downloadBase: baseDir,
            tokenizerFolder: baseDir,
            download: true,
            useBackgroundDownloadSession: false
        )
        config.verbose = false
        whisperKit = try await WhisperKit(config)
    }

    /// Initializes WhisperKit from a pre-downloaded model folder.
    /// No-op if that model is already loaded — loading a large model is a burst of
    /// heavy CPU/Neural Engine work, so it's done once and kept between recordings.
    func initialize(modelFolder: String) async throws {
        if whisperKit != nil, loadedModelFolder == modelFolder { return }

        let manager = ModelDownloadManager()
        manager.cleanCache()

        // Ensure tokenizer files exist — WhisperKit's tokenizer loader needs them
        // to avoid falling through to a buggy HuggingFace Hub download.
        let modelURL = URL(fileURLWithPath: modelFolder)
        await manager.ensureTokenizerFiles(in: modelURL)

        // Set tokenizerFolder to our model directory so WhisperKit doesn't fall back
        // to ~/Documents/huggingface (HubApi's default), which triggers a macOS
        // Documents folder permission prompt.
        let config = WhisperKitConfig(
            modelFolder: modelFolder,
            tokenizerFolder: modelURL,
            download: false,
            useBackgroundDownloadSession: false
        )
        config.verbose = false
        let start = Date()
        whisperKit = try await WhisperKit(config)
        loadedModelFolder = modelFolder
        ModelDownloadManager.markPrewarmed(modelFolder: modelURL)
        logger.notice("Loaded model \(modelURL.lastPathComponent, privacy: .public) in \(Date().timeIntervalSince(start), format: .fixed(precision: 1))s")
    }

    /// Releases the model's memory and Neural Engine resources.
    func unloadModel() async {
        guard !isTranscribing, let whisperKit else { return }
        await whisperKit.unloadModels()
        self.whisperKit = nil
        loadedModelFolder = nil
        logger.notice("Unloaded transcription model")
    }

    /// An audio stream to transcribe, tagged with the speaker it belongs to.
    struct AudioSource {
        let ringBuffer: RingBuffer
        /// Speaker ID applied to every segment (nil = unknown, assigned by diarization later).
        let speakerId: String?
        /// When set, chunks with no 100ms window louder than this RMS are skipped
        /// (avoids Whisper hallucinating on a silent mic).
        let silenceThreshold: Float?

        init(ringBuffer: RingBuffer, speakerId: String? = nil, silenceThreshold: Float? = nil) {
            self.ringBuffer = ringBuffer
            self.speakerId = speakerId
            self.silenceThreshold = silenceThreshold
        }
    }

    /// Starts real-time transcription from a single ring buffer.
    func startTranscription(meetingId: String, ringBuffer: RingBuffer) {
        startTranscription(meetingId: meetingId, sources: [AudioSource(ringBuffer: ringBuffer)])
    }

    /// Starts real-time transcription of one or more audio sources. Sources share
    /// one WhisperKit instance and are transcribed in turn, in array order.
    func startTranscription(meetingId: String, sources: [AudioSource]) {
        guard !isTranscribing, !sources.isEmpty else { return }

        self.meetingId = meetingId
        isTranscribing = true

        // Low priority so meeting apps (video, effects) win when competing for
        // CPU / Neural Engine time. Real-time is still met with headroom.
        Task.detached(priority: .utility) { [self] in
            await transcriptionLoop(sources: sources)
        }
    }

    /// Stops transcription.
    func stopTranscription() {
        isTranscribing = false
        meetingId = nil
    }

    /// Whether the service is currently transcribing.
    var active: Bool { isTranscribing }

    /// Returns true if running on Apple Silicon (real-time capable).
    static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Transcription Loop

    private func transcriptionLoop(sources: [AudioSource]) async {
        let chunkSamples = Int(chunkDuration * sampleRate)
        let advanceSamples = chunkSamples - Int(overlapDuration * sampleRate)
        var chunkStartMs = [Int64](repeating: 0, count: sources.count)

        while isTranscribing {
            // Wait until at least one source has a full chunk
            while isTranscribing && !sources.contains(where: { $0.ringBuffer.count >= chunkSamples }) {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            guard isTranscribing, let whisperKit else { break }

            for (index, source) in sources.enumerated() where isTranscribing {
                guard source.ringBuffer.count >= chunkSamples else { continue }

                let samples = source.ringBuffer.read(count: advanceSamples)
                guard !samples.isEmpty else { continue }

                let startMs = chunkStartMs[index]
                // Advance before transcribing so a failed chunk doesn't shift later timestamps
                chunkStartMs[index] += Int64(Double(samples.count) / sampleRate * 1000)

                if let threshold = source.silenceThreshold, Self.isSilent(samples, threshold: threshold) {
                    logger.debug("Skipping silent chunk at \(startMs)ms (speaker: \(source.speakerId ?? "system"))")
                    continue
                }

                await transcribeChunk(samples, startMs: startMs, speakerId: source.speakerId, whisperKit: whisperKit)
            }
        }
    }

    private func transcribeChunk(_ samples: [Float], startMs chunkStartMs: Int64, speakerId: String?, whisperKit: WhisperKit) async {
        // Log audio level to diagnose silence/hallucination issues
        let rms = sqrt(samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count))
        logger.notice("Chunk \(chunkStartMs)ms [\(speakerId ?? "system")]: \(samples.count) samples, RMS=\(rms)")

        // Transcribe the chunk with word timestamps for diarization alignment
        let decodeOptions = DecodingOptions(
            wordTimestamps: true,
            chunkingStrategy: .none
        )

        do {
            let results: [TranscriptionResult] = try await whisperKit.transcribe(
                audioArray: samples,
                decodeOptions: decodeOptions
            )

            for result in results {
                for wkSegment in result.segments {
                    let startMs = chunkStartMs + Int64(wkSegment.start * 1000)
                    let endMs = chunkStartMs + Int64(wkSegment.end * 1000)

                    logger.notice("Segment: noSpeechProb=\(wkSegment.noSpeechProb) text=\"\(wkSegment.text)\"")

                    let cleanedText = Self.cleanTranscriptText(wkSegment.text)
                    guard !cleanedText.isEmpty else { continue }

                    let segment = TranscriptSegment(
                        meetingId: meetingId ?? "",
                        startMs: startMs,
                        endMs: endMs,
                        speakerId: speakerId,
                        text: cleanedText,
                        confidence: Double(1.0 - wkSegment.noSpeechProb)
                    )
                    onSegment?(segment)
                }
            }
        } catch {
            logger.error("Transcription chunk error: \(error.localizedDescription)")
        }
    }

    /// Returns true if no 100ms window (at 16 kHz) reaches the RMS threshold.
    static func isSilent(_ samples: [Float], threshold: Float) -> Bool {
        let windowSize = 1600
        var start = 0
        while start < samples.count {
            let end = min(start + windowSize, samples.count)
            var sumSquares: Float = 0
            for i in start..<end {
                sumSquares += samples[i] * samples[i]
            }
            if sqrt(sumSquares / Float(end - start)) >= threshold {
                return false
            }
            start = end
        }
        return true
    }

    /// Transcribes a complete audio file (used for Intel batch mode).
    /// - Parameters:
    ///   - audioPath: Path to the audio file.
    ///   - meetingId: Meeting ID for segment attribution.
    ///   - onSegment: Callback for each transcribed segment.
    func transcribeFile(audioPath: String, meetingId: String, onSegment: @escaping (TranscriptSegment) -> Void) async throws {
        guard let whisperKit else {
            throw TranscriptionError.notInitialized
        }

        let decodeOptions = DecodingOptions(
            wordTimestamps: true,
            chunkingStrategy: .vad
        )

        let results: [TranscriptionResult] = try await whisperKit.transcribe(
            audioPath: audioPath,
            decodeOptions: decodeOptions
        )

        for result in results {
            for wkSegment in result.segments {
                let cleanedText = Self.cleanTranscriptText(wkSegment.text)
                guard !cleanedText.isEmpty else { continue }

                let segment = TranscriptSegment(
                    meetingId: meetingId,
                    startMs: Int64(wkSegment.start * 1000),
                    endMs: Int64(wkSegment.end * 1000),
                    text: cleanedText,
                    confidence: Double(1.0 - wkSegment.noSpeechProb)
                )
                onSegment(segment)
            }
        }
    }

    /// Strips WhisperKit hallucination tags and artifacts from transcript text.
    static func cleanTranscriptText(_ text: String) -> String {
        var cleaned = text
        // Remove WhisperKit timestamp tokens (e.g. <|6.00|>, <|0.00|>)
        cleaned = cleaned.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        )
        // Remove XML/HTML-style tags (e.g. <start of transcript>, <end>, <silence>)
        cleaned = cleaned.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )
        // Remove common Whisper hallucinations
        let hallucinations = [
            "Thank you for watching.",
            "Thanks for watching.",
            "Thank you for listening.",
            "Thanks for listening.",
            "Subscribe to my channel.",
            "Please subscribe.",
        ]
        for phrase in hallucinations {
            cleaned = cleaned.replacingOccurrences(of: phrase, with: "")
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }
}

enum TranscriptionError: Error {
    case notInitialized
    case modelNotFound
}
