import Foundation
import AVFoundation

/// Detects hardware and provides batch-mode transcription fallback for Intel Macs.
/// Intel Macs run WhisperKit at ~1.0x RTF — real-time transcription is not viable.
enum IntelFallback {
    /// Returns true if running on Intel (x86_64) hardware.
    static var isIntelMac: Bool {
        #if arch(x86_64)
        return true
        #else
        return false
        #endif
    }

    /// Returns true if real-time transcription is supported (Apple Silicon).
    static var supportsRealTimeTranscription: Bool {
        !isIntelMac
    }

    /// Transcription strategy based on hardware.
    enum Strategy {
        /// Real-time streaming transcription during recording (Apple Silicon).
        case realTime
        /// Batch transcription after meeting ends (Intel).
        case postMeeting
    }

    /// Returns the recommended transcription strategy for this hardware.
    static var recommendedStrategy: Strategy {
        supportsRealTimeTranscription ? .realTime : .postMeeting
    }

    /// Performs batch transcription of a complete audio file (Intel fallback).
    static func batchTranscribe(
        audioURL: URL,
        meetingId: String,
        transcriptionService: TranscriptionService,
        onSegment: @escaping (TranscriptSegment) -> Void
    ) async throws {
        try await transcriptionService.transcribeFile(
            audioPath: audioURL.path,
            meetingId: meetingId,
            onSegment: onSegment
        )
    }
}
