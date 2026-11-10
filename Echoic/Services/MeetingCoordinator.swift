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

    private lazy var audioCaptureService = AudioCaptureService()
    private let micCaptureService = MicrophoneCaptureService()
    private let transcriptionService = TranscriptionService()
    private let diarizationService = DiarizationService()
    private let localSpeakerIdentifier = LocalSpeakerIdentifier()
    private var transcriptionStore: TranscriptionStore?
    private var modelLoadTask: Task<Void, Error>?
    private var modelUnloadTask: Task<Void, Never>?
    /// Keep the model loaded this long after a recording (or a dismissed prompt)
    /// so back-to-back meetings don't pay the load cost again.
    private static let modelIdleUnloadDelay: UInt64 = 10 * 60 * 1_000_000_000
    /// Mic chunks with no 100ms window above this RMS are treated as silence.
    private static let micSilenceThreshold: Float = 0.01
    private var enableMicrophone = false
    /// True when the mic is transcribed as its own "You" track (System Audio mode).
    private var micTranscribedSeparately = false

    /// UserDefaults key for "Transcribe my microphone" (Settings → Audio).
    nonisolated static let microphoneSettingKey = "enableMicrophone"

    /// Whether to capture and transcribe the user's mic in System Audio mode (on by default).
    nonisolated static func transcribesMicrophone(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: microphoneSettingKey) as? Bool ?? true
    }

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
            enableMicrophone = false
            micTranscribedSeparately = false

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

            // Choose audio sources based on recording mode
            var transcriptionSources: [TranscriptionService.AudioSource]
            if recordingMode == .microphone {
                // Microphone mode: mic is the primary audio source.
                // On non-sandboxed macOS, AVAudioEngine.start() triggers the
                // system permission prompt directly — no pre-check needed.
                try micCaptureService.startCapture(meetingId: meeting.id)
                enableMicrophone = true
                transcriptionSources = [.init(ringBuffer: micCaptureService.micBuffer)]
            } else {
                // System audio mode: ScreenCaptureKit captures the other participants
                try await audioCaptureService.startCapture(meetingId: meeting.id)
                transcriptionSources = [.init(ringBuffer: audioCaptureService.ringBuffer)]

                // Your own voice never plays through system audio, so transcribe the
                // mic as a separate "You" track. Non-fatal if the mic is unavailable.
                if enableMic || Self.transcribesMicrophone() {
                    do {
                        try micCaptureService.startCapture()
                        enableMicrophone = true
                        micTranscribedSeparately = true
                        transcriptionSources.append(.init(
                            ringBuffer: micCaptureService.micBuffer,
                            speakerId: TranscriptSegment.localSpeakerId,
                            silenceThreshold: Self.micSilenceThreshold
                        ))
                    } catch {
                        logger.error("Mic capture failed (non-fatal): \(error.localizedDescription)")
                        errorMessage = "Microphone unavailable — only other participants will be transcribed. \(error.localizedDescription)"
                    }
                }
            }

            // Start transcription (if Apple Silicon).
            // Non-fatal: recording continues even if transcription fails.
            // Batch transcription can recover the transcript after the meeting.
            if IntelFallback.supportsRealTimeTranscription {
                do {
                    try await prepareTranscriptionModel()
                    transcriptionService.onSegment = { [weak self] segment in
                        Task { @MainActor in
                            self?.handleNewSegment(segment)
                        }
                    }
                    transcriptionService.startTranscription(
                        meetingId: meeting.id,
                        sources: transcriptionSources
                    )
                } catch {
                    logger.error("Transcription init failed (non-fatal): \(error.localizedDescription)")
                    errorMessage = "Live transcription unavailable: \(error.localizedDescription)"
                }
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

            let nsError = error as NSError
            logger.error("Recording failed: \(nsError.domain) code=\(nsError.code) \(error.localizedDescription)")
            let message = error.localizedDescription
            state = .error(message)
            errorMessage = message
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
                    try await prepareTranscriptionModel()
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

                        // Local speaker identification by voice matching — only needed
                        // when the mic wasn't already transcribed as its own track.
                        if enableMicrophone && !micTranscribedSeparately {
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
            scheduleModelUnload()

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
            scheduleModelUnload()
        }
    }

    // MARK: - Model Lifecycle

    /// Loads the transcription model if it isn't already, at low priority.
    /// Concurrent callers share one load. Called when a recording starts and
    /// when a meeting is detected (so the model is warm before Start is clicked).
    func prepareTranscriptionModel() async throws {
        modelUnloadTask?.cancel()
        modelUnloadTask = nil

        if let inFlight = modelLoadTask {
            try await inFlight.value
            return
        }

        let service = transcriptionService
        let task = Task.detached(priority: .utility) {
            if let modelPath = ModelDownloadManager().bestAvailableModelPath() {
                try await service.initialize(modelFolder: modelPath)
            } else {
                try await service.initialize()
            }
        }
        modelLoadTask = task
        defer { modelLoadTask = nil }
        try await task.value
    }

    /// Unloads the model after an idle period, unless a recording starts first.
    func scheduleModelUnload() {
        modelUnloadTask?.cancel()
        modelUnloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.modelIdleUnloadDelay)
            guard !Task.isCancelled, let self, self.state != .recording, self.modelLoadTask == nil else { return }
            await self.transcriptionService.unloadModel()
        }
    }

    // MARK: - Segment Handling

    private func handleNewSegment(_ segment: TranscriptSegment) {
        do {
            // Only surface segments that were actually stored (not deduplicated),
            // so the live transcript matches what's persisted.
            if let stored = try transcriptionStore?.insert(segment) {
                // System and mic tracks arrive out of order; keep time order
                liveSegments.insertByStartTime(stored)
            }
        } catch {
            // Log but don't interrupt recording
            logger.error("Failed to store transcript segment: \(error.localizedDescription)")
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
