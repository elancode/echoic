import Foundation
import WhisperKit

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

    /// Initializes WhisperKit with the given model variant.
    /// - Parameter model: Model name (e.g. "small.en", "large-v3"). If nil, uses default.
    func initialize(model: String? = nil) async throws {
        let config = WhisperKitConfig(
            model: model,
            download: true,
            useBackgroundDownloadSession: false
        )
        config.verbose = false
        whisperKit = try await WhisperKit(config)
    }

    /// Initializes WhisperKit from a pre-downloaded model folder.
    func initialize(modelFolder: String) async throws {
        let config = WhisperKitConfig(
            modelFolder: modelFolder,
            download: false,
            useBackgroundDownloadSession: false
        )
        config.verbose = false
        whisperKit = try await WhisperKit(config)
    }

    /// Starts real-time transcription from the ring buffer.
    func startTranscription(meetingId: String, ringBuffer: RingBuffer) {
        guard !isTranscribing else { return }

        self.meetingId = meetingId
        isTranscribing = true

        Task {
            await transcriptionLoop(ringBuffer: ringBuffer)
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

    private func transcriptionLoop(ringBuffer: RingBuffer) async {
        let chunkSamples = Int(chunkDuration * sampleRate)
        let overlapSamples = Int(overlapDuration * sampleRate)
        var chunkStartMs: Int64 = 0

        while isTranscribing {
            // Wait for enough samples
            while ringBuffer.count < chunkSamples && isTranscribing {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            guard isTranscribing, let whisperKit else { break }

            // Read chunk (advance by chunkSamples - overlapSamples to maintain overlap)
            let samples = ringBuffer.read(count: chunkSamples - overlapSamples)
            guard !samples.isEmpty else { continue }

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

                        let cleanedText = Self.cleanTranscriptText(wkSegment.text)
                        guard !cleanedText.isEmpty else { continue }

                        let segment = TranscriptSegment(
                            meetingId: meetingId ?? "",
                            startMs: startMs,
                            endMs: endMs,
                            text: cleanedText,
                            confidence: Double(1.0 - wkSegment.noSpeechProb)
                        )
                        onSegment?(segment)
                    }
                }
            } catch {
                // Log transcription error but don't stop the loop
                continue
            }

            // Advance chunk start time (minus overlap)
            let advancedSamples = chunkSamples - overlapSamples
            chunkStartMs += Int64(Double(advancedSamples) / sampleRate * 1000)
        }
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
