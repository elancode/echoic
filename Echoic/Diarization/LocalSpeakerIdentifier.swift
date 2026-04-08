import Foundation
import GRDB
import WhisperKit

/// Identifies the local user ("You") by comparing microphone audio embeddings
/// with speaker clusters from diarization.
///
/// Uses a simple energy/spectral comparison as a baseline. When SpeakerKit Pro
/// is available, this can be upgraded to neural speaker embeddings.
final class LocalSpeakerIdentifier {
    /// Compares mic audio embeddings against diarization speaker clusters
    /// to identify which speaker is the local user.
    func identify(
        micBuffer: RingBuffer,
        speakerSegments: [DiarizationService.DiarizationSegment],
        audioURL: URL
    ) async throws -> String? {
        let micSamples = micBuffer.peek()
        guard micSamples.count >= 16000 else { return nil } // Need at least 1 second

        // Extract embedding from mic audio
        let micEmbedding = extractEmbedding(from: micSamples)

        // Load meeting audio
        let meetingAudio = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)

        // Extract embeddings for each speaker
        var bestMatch: String?
        var bestSimilarity: Float = -1

        let uniqueSpeakers = Set(speakerSegments.map(\.speakerId))

        for speakerId in uniqueSpeakers {
            let speakerSamples = collectSamples(
                for: speakerId,
                segments: speakerSegments,
                audio: meetingAudio
            )

            guard speakerSamples.count >= 16000 else { continue }

            let speakerEmbedding = extractEmbedding(from: speakerSamples)
            let similarity = cosineSimilarity(micEmbedding, speakerEmbedding)

            if similarity > bestSimilarity {
                bestSimilarity = similarity
                bestMatch = speakerId
            }
        }

        // Threshold for positive identification
        guard bestSimilarity > 0.7 else { return nil }

        return bestMatch
    }

    /// Relabels the identified speaker as "you" in the database.
    func relabel(
        speakerId: String,
        meetingId: String,
        databaseWriter: any DatabaseWriter
    ) throws {
        try databaseWriter.write { db in
            try db.execute(
                sql: "UPDATE transcriptSegment SET speakerId = ? WHERE meetingId = ? AND speakerId = ?",
                arguments: ["you", meetingId, speakerId]
            )
            try db.execute(
                sql: "UPDATE meetingSpeaker SET speakerId = ?, label = ? WHERE meetingId = ? AND speakerId = ?",
                arguments: ["you", "You", meetingId, speakerId]
            )
        }
    }

    // MARK: - Embeddings

    /// Extracts a simple spectral feature embedding from audio samples.
    /// This provides a basic speaker similarity metric. For production quality,
    /// SpeakerKit's neural embedder should be used directly when speaker
    /// verification APIs become available.
    private func extractEmbedding(from samples: [Float]) -> [Float] {
        let windowSize = 400 // 25ms at 16kHz
        let hopSize = 160 // 10ms at 16kHz
        let numFeatures = 40

        var features = [Float](repeating: 0, count: numFeatures)
        var windowCount = 0

        var offset = 0
        while offset + windowSize <= min(samples.count, 16000 * 30) { // Max 30s
            let window = Array(samples[offset..<(offset + windowSize)])
            for band in 0..<numFeatures {
                let start = band * windowSize / numFeatures
                let end = (band + 1) * windowSize / numFeatures
                let energy = window[start..<end].reduce(0) { $0 + $1 * $1 }
                features[band] += energy
            }
            windowCount += 1
            offset += hopSize
        }

        if windowCount > 0 {
            for i in 0..<numFeatures {
                features[i] /= Float(windowCount)
            }
        }

        return features
    }

    private func collectSamples(
        for speakerId: String,
        segments: [DiarizationService.DiarizationSegment],
        audio: [Float]
    ) -> [Float] {
        var samples: [Float] = []
        let sampleRate: Double = 16000

        for segment in segments where segment.speakerId == speakerId {
            let startSample = Int(Double(segment.startMs) / 1000.0 * sampleRate)
            let endSample = min(Int(Double(segment.endMs) / 1000.0 * sampleRate), audio.count)

            if startSample < endSample && endSample <= audio.count {
                samples.append(contentsOf: audio[startSample..<endSample])
            }

            if samples.count >= Int(30 * sampleRate) { break }
        }

        return samples
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }
}
