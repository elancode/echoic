import Foundation
import AVFoundation
import os.log

private let audioFileLogger = Logger(subsystem: "com.echoic.app", category: "AudioFiles")

/// Manages meeting audio files: segment storage and concatenation.
/// Critical Rule #8: Segments flushed every 30s during recording.
/// Critical Rule #10: Files stored in user-accessible standard formats.
enum AudioFileManager {
    private static let meetingsDirectory = "meetings"

    /// Returns the base URL for all meeting data.
    static func baseURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("Echoic", isDirectory: true)
    }

    /// Returns the directory for a specific meeting's audio.
    static func meetingDirectory(meetingId: String) throws -> URL {
        let base = try baseURL()
        return base
            .appendingPathComponent(meetingsDirectory, isDirectory: true)
            .appendingPathComponent(meetingId, isDirectory: true)
    }

    /// Returns the segments directory for a meeting.
    static func segmentsDirectory(meetingId: String) throws -> URL {
        let dir = try meetingDirectory(meetingId: meetingId)
        return dir.appendingPathComponent("segments", isDirectory: true)
    }

    /// Returns the final audio file path for a meeting.
    static func finalAudioURL(meetingId: String) throws -> URL {
        let dir = try meetingDirectory(meetingId: meetingId)
        return dir.appendingPathComponent("audio.m4a")
    }

    /// Concatenates AAC segment files into a single .m4a file.
    /// - Parameters:
    ///   - segments: Ordered list of segment file URLs.
    ///   - outputURL: Destination for the combined file.
    static func concatenateSegments(_ segments: [URL], to outputURL: URL) async throws {
        guard !segments.isEmpty else { return }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioFileError.compositionFailed
        }

        var currentTime = CMTime.zero
        var joined = 0

        for segmentURL in segments {
            // A segment that can't be read (typically the last one of a recording
            // cut short by a crash or quit) is skipped: it costs at most 30 s of
            // audio instead of the whole meeting.
            do {
                let asset = AVURLAsset(url: segmentURL)
                let duration = try await asset.load(.duration)
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                guard let audioTrack = tracks.first, duration > .zero else {
                    audioFileLogger.warning("Skipping empty segment \(segmentURL.lastPathComponent, privacy: .public)")
                    continue
                }
                try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audioTrack, at: currentTime)
                currentTime = CMTimeAdd(currentTime, duration)
                joined += 1
            } catch {
                audioFileLogger.warning(
                    "Skipping unreadable segment \(segmentURL.lastPathComponent, privacy: .public): \(error.localizedDescription)"
                )
            }
        }

        guard joined > 0 else { throw AudioFileError.noReadableSegments }

        // Export as M4A
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioFileError.exportFailed
        }

        // Export to a temporary file and move it into place only when complete, so an
        // interrupted export (app quit, crash) never leaves a truncated audio.m4a behind.
        let partialURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent("\(outputURL.deletingPathExtension().lastPathComponent).partial.m4a")
        try? FileManager.default.removeItem(at: partialURL)

        session.outputURL = partialURL
        session.outputFileType = .m4a

        await session.export()

        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: partialURL)
            throw AudioFileError.exportFailed
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: partialURL)
        } else {
            try FileManager.default.moveItem(at: partialURL, to: outputURL)
        }
    }

    /// True if the file exists, opens as audio, and contains at least one frame.
    /// Partially written .m4a files (no `moov` box) fail to open.
    static func isReadableAudio(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let file = try? AVAudioFile(forReading: url) else {
            return false
        }
        return file.length > 0
    }

    /// Cleans up segment files after successful concatenation.
    static func cleanupSegments(meetingId: String) throws {
        let segDir = try segmentsDirectory(meetingId: meetingId)
        if FileManager.default.fileExists(atPath: segDir.path) {
            try FileManager.default.removeItem(at: segDir)
        }
    }

    /// Deletes all files for a meeting.
    static func deleteMeetingFiles(meetingId: String) throws {
        let dir = try meetingDirectory(meetingId: meetingId)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    /// Returns the relative path from the base URL for database storage.
    static func relativePath(meetingId: String) -> String {
        "\(meetingsDirectory)/\(meetingId)/audio.m4a"
    }
}

enum AudioFileError: Error, Equatable {
    case compositionFailed
    case exportFailed
    case segmentNotFound
    /// Every segment was unreadable, so there's no audio to join.
    case noReadableSegments
}
