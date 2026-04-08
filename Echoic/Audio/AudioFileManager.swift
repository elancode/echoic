import Foundation
import AVFoundation

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

        for segmentURL in segments {
            let asset = AVURLAsset(url: segmentURL)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .audio)

            guard let audioTrack = tracks.first else { continue }

            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: audioTrack,
                at: currentTime
            )

            currentTime = CMTimeAdd(currentTime, duration)
        }

        // Export as M4A
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioFileError.exportFailed
        }

        session.outputURL = outputURL
        session.outputFileType = .m4a

        await session.export()

        guard session.status == .completed else {
            throw AudioFileError.exportFailed
        }
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

enum AudioFileError: Error {
    case compositionFailed
    case exportFailed
    case segmentNotFound
}
