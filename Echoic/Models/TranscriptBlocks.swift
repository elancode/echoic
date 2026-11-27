import Foundation

/// A run of consecutive transcript segments from one speaker.
struct TranscriptBlock: Identifiable, Equatable {
    /// Start of the first segment; doubles as the scroll anchor for timestamp links.
    var id: Int64 { startMs }
    let startMs: Int64
    let speakerId: String?
    let label: String
    let text: String
}

enum TranscriptBlocks {
    /// Groups consecutive segments by speaker name. Labels come from `meetingSpeaker`
    /// (names), falling back to "You" / "Speaker N". Two speaker IDs merged to the
    /// same name (diarization split one person) form one block.
    static func make(from segments: [TranscriptSegment], labels: [String: String]) -> [TranscriptBlock] {
        var blocks: [TranscriptBlock] = []
        var current: (start: Int64, speaker: String?, label: String, texts: [String])?

        func flush() {
            guard let run = current else { return }
            blocks.append(TranscriptBlock(
                startMs: run.start, speakerId: run.speaker, label: run.label,
                text: run.texts.joined(separator: " ")
            ))
        }

        for segment in segments.sorted(by: { $0.startMs < $1.startMs }) {
            let label = segment.speakerId.map { labels[$0] ?? SpeakerMerge.defaultLabel(for: $0) } ?? "Unknown"
            if let run = current, run.label == label {
                current?.texts.append(segment.text)
            } else {
                flush()
                current = (segment.startMs, segment.speakerId, label, [segment.text])
            }
        }
        flush()
        return blocks
    }

    /// The block a timestamp falls in: the last block starting at or before it.
    static func blockId(containing ms: Int64, in blocks: [TranscriptBlock]) -> Int64? {
        blocks.last(where: { $0.startMs <= ms })?.id ?? blocks.first?.id
    }
}
