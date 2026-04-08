import Foundation
import GRDB
import os.log

private let logger = Logger(subsystem: "com.echoic.app", category: "PostProcessing")

/// Resumes post-processing (diarization + summarization) for meetings
/// that were interrupted (e.g. laptop lid closed, crash).
enum PostProcessingService {

    /// Finds unprocessed meetings and runs diarization + summarization.
    static func resumeUnfinished(databaseWriter: any DatabaseWriter) async {
        let meetings: [Meeting] = (try? await databaseWriter.read { db in
            try Meeting
                .filter(Meeting.Columns.processed == false)
                .filter(Meeting.Columns.status != Meeting.Status.recording.rawValue)
                .fetchAll(db)
        }) ?? []

        guard !meetings.isEmpty else { return }
        logger.info("Found \(meetings.count) unfinished meeting(s) to post-process")

        let diarizationService = DiarizationService()

        for meeting in meetings {
            await postProcess(meeting: meeting, diarizationService: diarizationService, databaseWriter: databaseWriter)
        }
    }

    /// If the final audio.m4a doesn't exist but segment files do, concatenate them.
    /// This handles crash/lid-close recovery where stopCapture never ran.
    private static func ensureFinalAudio(meetingId: String) async -> Bool {
        do {
            let audioURL = try AudioFileManager.finalAudioURL(meetingId: meetingId)
            if FileManager.default.fileExists(atPath: audioURL.path) {
                return true
            }

            // Check for segment files
            let segDir = try AudioFileManager.segmentsDirectory(meetingId: meetingId)
            guard FileManager.default.fileExists(atPath: segDir.path) else {
                logger.info("No segments directory for \(meetingId)")
                return false
            }

            let segmentFiles = try FileManager.default
                .contentsOfDirectory(at: segDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "m4a" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            guard !segmentFiles.isEmpty else {
                logger.info("No segment files found for \(meetingId)")
                return false
            }

            logger.info("Concatenating \(segmentFiles.count) segments for \(meetingId)")
            try await AudioFileManager.concatenateSegments(segmentFiles, to: audioURL)
            try AudioFileManager.cleanupSegments(meetingId: meetingId)
            logger.info("Audio recovered for \(meetingId)")
            return true
        } catch {
            logger.error("Failed to recover audio for \(meetingId): \(error)")
            return false
        }
    }

    private static func postProcess(meeting: Meeting, diarizationService: DiarizationService, databaseWriter: any DatabaseWriter) async {
        logger.info("Post-processing meeting \(meeting.id): \(meeting.title)")

        // Check if transcript segments already have speaker IDs
        let needsDiarization: Bool = (try? await databaseWriter.read { db in
            let count = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM transcriptSegment
                WHERE meetingId = ? AND speakerId IS NOT NULL
                """, arguments: [meeting.id])
            return (count ?? 0) == 0
        }) ?? true

        // Try diarization if segments lack speaker IDs
        if needsDiarization {
            // Recover audio from segments if final file is missing (crash/lid-close)
            let audioAvailable = await ensureFinalAudio(meetingId: meeting.id)

            if audioAvailable {
                do {
                    let audioURL = try AudioFileManager.finalAudioURL(meetingId: meeting.id)
                    logger.info("Running diarization for \(meeting.id)")
                    let speakerSegments = try await diarizationService.diarize(audioURL: audioURL)
                    try SpeakerMerge.merge(
                        meetingId: meeting.id,
                        speakerSegments: speakerSegments,
                        databaseWriter: databaseWriter
                    )
                    logger.info("Diarization complete: \(speakerSegments.count) segments")
                } catch {
                    logger.error("Diarization failed for \(meeting.id): \(error)")
                }
            } else {
                logger.warning("No audio available for \(meeting.id), skipping diarization")
            }
        }

        // Check if summary exists
        let needsSummary: Bool = (try? await databaseWriter.read { db in
            try Summary.fetchOne(db, key: meeting.id) == nil
        }) ?? true

        var summarizationSucceeded = !needsSummary
        if needsSummary {
            do {
                logger.info("Running summarization for \(meeting.id)")
                let summarizer = SummarizationService(databaseWriter: databaseWriter)
                try await summarizer.summarize(meetingId: meeting.id)
                logger.info("Summarization complete for \(meeting.id)")
                summarizationSucceeded = true
            } catch {
                logger.error("Summarization failed for \(meeting.id): \(error)")
            }
        }

        // Clean up audio files
        try? AudioFileManager.deleteMeetingFiles(meetingId: meeting.id)

        // Mark as ready; only mark processed if summarization succeeded
        do {
            try await databaseWriter.write { db in
                if var m = try Meeting.fetchOne(db, key: meeting.id) {
                    m.audioPath = nil
                    m.status = .ready
                    m.processed = summarizationSucceeded
                    try m.update(db)
                }
            }
            logger.info("Meeting \(meeting.id) marked as ready (processed=\(summarizationSucceeded))")
        } catch {
            logger.error("Failed to update meeting \(meeting.id): \(error)")
        }
    }
}
