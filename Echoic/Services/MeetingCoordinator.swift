import AppKit
import Foundation
import GRDB
import Combine
import os.log

private let logger = Logger(subsystem: "com.echoic.app", category: "MeetingCoordinator")

/// Orchestrates the full recording flow:
/// Start → capture + transcribe → Stop → diarize + summarize → ready.
/// This is the central coordinator that ties all services together.
@MainActor
final class MeetingCoordinator: ObservableObject {
    static let shared = MeetingCoordinator()

    @Published var state: MeetingState = .idle
    @Published var currentMeeting: Meeting?
    @Published var liveSegments: [TranscriptSegment] = []
    @Published var errorMessage: String?
    @Published var recordingMode: RecordingMode = .systemAudio

    private let audioCaptureService = AudioCaptureService()
    private let micCaptureService = MicrophoneCaptureService()
    private let transcriptionService = TranscriptionService()
    private let diarizationService = DiarizationService()
    private let localSpeakerIdentifier = LocalSpeakerIdentifier()
    private var transcriptionStore: TranscriptionStore?
    private var enableMicrophone = false

    /// The database writer for all operations.
    var databaseWriter: (any DatabaseWriter)?

    // MARK: - Recording Flow

    /// Starts a new recording session.
    func startRecording(enableMic: Bool = false) async {
        guard state == .idle || state.errorText != nil else { return }

        // Reset error state so we start clean
        if state.errorText != nil {
            state = .idle
            errorMessage = nil
        }

        do {
            let meeting = Meeting.create()
            enableMicrophone = enableMic || recordingMode == .microphone

            // Insert meeting into database
            guard let db = databaseWriter else {
                logger.error("No database writer available — cannot start recording")
                state = .error("Database not available. Try restarting Echoic.")
                return
            }

            try await db.write { dbConn in
                try meeting.insert(dbConn)
            }

            // Now safe to update published state (after first suspension point)
            currentMeeting = meeting
            state = .recording

            // Set up transcription store
            transcriptionStore = TranscriptionStore(databaseWriter: db)
            transcriptionStore?.resetCache()

            // Choose audio source based on recording mode
            let transcriptionRingBuffer: RingBuffer
            if recordingMode == .microphone {
                // Microphone mode: mic is the primary audio source.
                // On non-sandboxed macOS, AVAudioEngine.start() triggers the
                // system permission prompt directly — no pre-check needed.
                try micCaptureService.startCapture(meetingId: meeting.id)
                transcriptionRingBuffer = micCaptureService.micBuffer
            } else {
                // System audio mode: ScreenCaptureKit is primary
                try await audioCaptureService.startCapture(meetingId: meeting.id)
                transcriptionRingBuffer = audioCaptureService.ringBuffer

                // Start mic capture for speaker ID if enabled
                if enableMic {
                    try micCaptureService.startCapture()
                }
            }

            // Start transcription (if Apple Silicon)
            if IntelFallback.supportsRealTimeTranscription {
                let modelManager = ModelDownloadManager()
                if let modelPath = modelManager.bestAvailableModelPath() {
                    try await transcriptionService.initialize(modelFolder: modelPath)
                } else {
                    try await transcriptionService.initialize()
                }
                transcriptionService.onSegment = { [weak self] segment in
                    Task { @MainActor in
                        self?.handleNewSegment(segment)
                    }
                }
                transcriptionService.startTranscription(
                    meetingId: meeting.id,
                    ringBuffer: transcriptionRingBuffer
                )
            }
        } catch {
            // Clean up any capture services that may have started before the error
            transcriptionService.stopTranscription()
            if micCaptureService.isCapturing {
                micCaptureService.stopCaptureSync()
            }
            if audioCaptureService.isCapturing {
                try? await audioCaptureService.stopCapture()
            }

            state = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    /// Stops the current recording and begins post-processing.
    func stopRecording() async {
        guard state == .recording, let meeting = currentMeeting else { return }

        state = .processing

        do {
            // Stop transcription
            transcriptionService.stopTranscription()

            // Stop audio capture (finalizes segments → single .m4a)
            logger.info("Stopping audio capture...")
            if recordingMode == .microphone {
                try await micCaptureService.stopCapture()
            } else {
                try await audioCaptureService.stopCapture()
                if enableMicrophone {
                    micCaptureService.stopCaptureSync()
                }
            }
            let finalAudioExists = FileManager.default.fileExists(atPath: (try? AudioFileManager.finalAudioURL(meetingId: meeting.id).path) ?? "")
            logger.info("Audio capture stopped. Final audio exists: \(finalAudioExists)")

            // Update meeting record
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            try await databaseWriter?.write { db in
                if var m = try Meeting.fetchOne(db, key: meeting.id) {
                    m.endedAt = now
                    m.durationMs = now - m.startedAt
                    m.audioPath = AudioFileManager.relativePath(meetingId: meeting.id)
                    m.status = .processing
                    try m.update(db)
                }
            }

            // Intel fallback: batch transcription
            if IntelFallback.isIntelMac {
                let audioURL = try AudioFileManager.finalAudioURL(meetingId: meeting.id)
                if transcriptionService.active == false {
                    let modelManager = ModelDownloadManager()
                    if let modelPath = modelManager.bestAvailableModelPath() {
                        try await transcriptionService.initialize(modelFolder: modelPath)
                    } else {
                        try await transcriptionService.initialize()
                    }
                }
                try await IntelFallback.batchTranscribe(
                    audioURL: audioURL,
                    meetingId: meeting.id,
                    transcriptionService: transcriptionService
                ) { [weak self] segment in
                    Task { @MainActor in
                        self?.handleNewSegment(segment)
                    }
                }
            }

            // Run diarization (non-fatal — transcript still works without speaker IDs)
            let audioURL = try AudioFileManager.finalAudioURL(meetingId: meeting.id)
            let audioExists = FileManager.default.fileExists(atPath: audioURL.path)
            logger.info("Diarization: audio at \(audioURL.path), exists=\(audioExists)")
            if audioExists {
                do {
                    logger.info("Starting diarization...")
                    let speakerSegments = try await diarizationService.diarize(audioURL: audioURL)
                    logger.info("Diarization complete: \(speakerSegments.count) segments")

                    if let db = databaseWriter {
                        try SpeakerMerge.merge(
                            meetingId: meeting.id,
                            speakerSegments: speakerSegments,
                            databaseWriter: db
                        )

                        // Local speaker identification
                        if enableMicrophone {
                            if let matchedSpeaker = try await localSpeakerIdentifier.identify(
                                micBuffer: micCaptureService.micBuffer,
                                speakerSegments: speakerSegments,
                                audioURL: audioURL
                            ) {
                                try localSpeakerIdentifier.relabel(
                                    speakerId: matchedSpeaker,
                                    meetingId: meeting.id,
                                    databaseWriter: db
                                )
                            }
                        }
                    }
                } catch {
                    logger.error("Diarization failed (non-fatal): \(error)")
                }
            }

            // Run summarization (non-fatal — meeting still saved without summary)
            var summarizationSucceeded = false
            do {
                if let db = databaseWriter {
                    let summarizer = SummarizationService(databaseWriter: db)
                    try await summarizer.summarize(meetingId: meeting.id)
                    summarizationSucceeded = true
                }
            } catch {
                logger.error("Summarization failed (non-fatal): \(error.localizedDescription)")
            }

            // Delete audio files — we only keep the transcript
            try? AudioFileManager.deleteMeetingFiles(meetingId: meeting.id)

            // Mark meeting as ready; only mark processed if summarization succeeded
            try await databaseWriter?.write { db in
                if var m = try Meeting.fetchOne(db, key: meeting.id) {
                    m.audioPath = nil
                    m.status = .ready
                    m.processed = summarizationSucceeded
                    try m.update(db)
                }
            }

            state = .idle
            currentMeeting = nil
            liveSegments = []

        } catch {
            // Ensure capture services are stopped even on error
            transcriptionService.stopTranscription()
            if micCaptureService.isCapturing {
                micCaptureService.stopCaptureSync()
            }
            if audioCaptureService.isCapturing {
                try? await audioCaptureService.stopCapture()
            }

            // Mark as error but preserve data
            try? await databaseWriter?.write { db in
                if var m = try Meeting.fetchOne(db, key: meeting.id) {
                    m.status = .error
                    try m.update(db)
                }
            }

            state = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Segment Handling

    private func handleNewSegment(_ segment: TranscriptSegment) {
        do {
            try transcriptionStore?.insert(segment)
            liveSegments.append(segment)
        } catch {
            // Log but don't interrupt recording
        }
    }
}

// MARK: - Meeting State

enum MeetingState: Equatable {
    case idle
    case recording
    case processing
    case error(String)

    static func == (lhs: MeetingState, rhs: MeetingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording), (.processing, .processing):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }

    var errorText: String? {
        if case .error(let msg) = self { return msg }
        return nil
    }

    var recordingState: RecordingState {
        switch self {
        case .idle, .error: return .idle
        case .recording: return .recording
        case .processing: return .processing
        }
    }
}

// MARK: - Recording Mode

enum RecordingMode: String, CaseIterable {
    case systemAudio = "System Audio"
    case microphone = "Microphone"

    var icon: String {
        switch self {
        case .systemAudio: return "display"
        case .microphone: return "mic"
        }
    }
}
