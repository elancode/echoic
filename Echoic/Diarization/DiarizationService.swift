import Foundation
import SpeakerKit
import WhisperKit

/// Post-meeting speaker diarization using SpeakerKit (Pyannote v3/v4 CoreML models).
/// Processes full audio file after recording ends, identifies 2–6 speakers.
/// Critical Rule #2: Runs in-process, no sidecars.
final class DiarizationService {
    /// Our internal segment type mapped from SpeakerKit's output.
    struct DiarizationSegment {
        let startMs: Int64
        let endMs: Int64
        let speakerId: String
    }

    private var speakerKit: SpeakerKit?

    /// Initializes SpeakerKit with default Pyannote config (downloads models on first use).
    func initialize() async throws {
        print("[DiarizationService] Initializing SpeakerKit (downloading models if needed)...")
        let config = PyannoteConfig(
            download: true,
            verbose: true
        )
        speakerKit = try await SpeakerKit(config)
        print("[DiarizationService] SpeakerKit initialized successfully")
    }

    /// Performs diarization on a complete audio file.
    /// - Parameters:
    ///   - audioURL: Path to the meeting .m4a file.
    ///   - numberOfSpeakers: Expected number of speakers (nil for auto-detect).
    /// - Returns: Ordered list of speaker segments.
    func diarize(audioURL: URL, numberOfSpeakers: Int? = nil) async throws -> [DiarizationSegment] {
        // Initialize if needed
        if speakerKit == nil {
            try await initialize()
        }

        guard let speakerKit else {
            throw DiarizationError.notInitialized
        }

        // Load audio as 16kHz mono float array
        print("[DiarizationService] Loading audio from: \(audioURL.path)")
        print("[DiarizationService] File exists: \(FileManager.default.fileExists(atPath: audioURL.path))")
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        print("[DiarizationService] Loaded \(samples.count) samples")

        // Configure diarization options
        let options = PyannoteDiarizationOptions(
            numberOfSpeakers: numberOfSpeakers
        )

        // Run diarization
        print("[DiarizationService] Starting diarization...")
        let result = try await speakerKit.diarize(
            audioArray: samples,
            options: options
        )
        print("[DiarizationService] Diarization complete: \(result.segments.count) segments, \(result.speakerCount) speakers")

        // Convert SpeakerKit segments to our internal type
        return result.segments.map { segment in
            let speakerId: String
            if let id = segment.speaker.speakerId {
                speakerId = "speaker_\(id + 1)"
            } else {
                speakerId = "speaker_unknown"
            }

            return DiarizationSegment(
                startMs: Int64(segment.startTime * 1000),
                endMs: Int64(segment.endTime * 1000),
                speakerId: speakerId
            )
        }
    }

    /// Performs diarization and aligns results with WhisperKit transcription results.
    /// Uses SpeakerKit's built-in addSpeakerInfo for word-level speaker alignment.
    func diarizeWithTranscription(
        audioURL: URL,
        transcriptionResults: [TranscriptionResult],
        numberOfSpeakers: Int? = nil
    ) async throws -> [[SpeakerSegment]] {
        if speakerKit == nil {
            try await initialize()
        }

        guard let speakerKit else {
            throw DiarizationError.notInitialized
        }

        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)

        let options = PyannoteDiarizationOptions(
            numberOfSpeakers: numberOfSpeakers
        )

        let result = try await speakerKit.diarize(
            audioArray: samples,
            options: options
        )

        // Use SpeakerKit's built-in transcript-speaker alignment
        return result.addSpeakerInfo(to: transcriptionResults, strategy: .subsegment)
    }

    /// Unloads models to free memory.
    func unloadModels() async {
        await speakerKit?.unloadModels()
        speakerKit = nil
    }
}

enum DiarizationError: Error {
    case notInitialized
    case noAudioFound
    case processingFailed
}
