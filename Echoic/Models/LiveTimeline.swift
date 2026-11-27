import Foundation

/// One speaker turn in the live transcript, split into paragraphs.
struct LiveTurn: Identifiable, Equatable {
    var id: Int64 { startMs }
    let startMs: Int64
    let speakerId: String?
    let label: String
    let paragraphs: [String]
}

/// A row in the live transcript: a turn or a bookmark marker.
struct LiveTimelineItem: Identifiable, Equatable {
    enum Kind: Equatable { case turn, bookmark }

    let kind: Kind
    let ms: Int64
    var turn: LiveTurn?

    var id: String { "\(kind == .turn ? "t" : "b")\(ms)" }
}

/// Builds the live transcript layout (live transcript handover §4).
///
/// Remote speakers can't be told apart until diarization runs after the meeting,
/// so everyone on the call is "Others". A turn starts when the label changes; within
/// a turn, a pause of 2 s or more, or 45 s of continuous speech, starts a paragraph.
enum LiveTimeline {
    static let othersLabel = "Others"
    static let paragraphPauseMs: Int64 = 2_000
    static let maxParagraphMs: Int64 = 45_000
    /// Content growth right after an automatic scroll isn't the user scrolling away.
    static let autoScrollGrace: TimeInterval = 0.6
    /// Within this distance of the bottom counts as "at the bottom".
    static let bottomTolerance: CGFloat = 40

    static func label(for speakerId: String?) -> String {
        guard let speakerId else { return othersLabel }
        return SpeakerMerge.defaultLabel(for: speakerId)
    }

    static func turns(from segments: [TranscriptSegment]) -> [LiveTurn] {
        var turns: [LiveTurn] = []
        var current: (start: Int64, speaker: String?, label: String, paragraphs: [[String]], paragraphStart: Int64, lastEnd: Int64)?

        func flush() {
            guard let run = current else { return }
            turns.append(LiveTurn(
                startMs: run.start, speakerId: run.speaker, label: run.label,
                paragraphs: run.paragraphs.map { $0.joined(separator: " ") }
            ))
        }

        for segment in segments.sorted(by: { $0.startMs < $1.startMs }) {
            let label = label(for: segment.speakerId)
            if var run = current, run.label == label {
                let pause = segment.startMs - run.lastEnd
                let length = segment.endMs - run.paragraphStart
                if pause >= paragraphPauseMs || length > maxParagraphMs {
                    run.paragraphs.append([segment.text])
                    run.paragraphStart = segment.startMs
                } else {
                    run.paragraphs[run.paragraphs.count - 1].append(segment.text)
                }
                run.lastEnd = max(run.lastEnd, segment.endMs)
                current = run
            } else {
                flush()
                current = (segment.startMs, segment.speakerId, label, [[segment.text]], segment.startMs, segment.endMs)
            }
        }
        flush()
        return turns
    }

    /// Turns and bookmark markers in time order. A bookmark sits before the first turn
    /// that starts after it.
    static func items(turns: [LiveTurn], bookmarks: [Int64]) -> [LiveTimelineItem] {
        let turnItems = turns.map { LiveTimelineItem(kind: .turn, ms: $0.startMs, turn: $0) }
        let markerItems = bookmarks.map { LiveTimelineItem(kind: .bookmark, ms: $0, turn: nil) }
        return (turnItems + markerItems).sorted { lhs, rhs in
            lhs.ms == rhs.ms ? lhs.kind == .turn : lhs.ms < rhs.ms
        }
    }

    /// Whether the transcript should keep following new text, given where the user is.
    static func isFollowing(current: Bool, distanceFromBottom: CGFloat, secondsSinceAutoScroll: TimeInterval) -> Bool {
        if distanceFromBottom <= bottomTolerance { return true }
        if current, secondsSinceAutoScroll < autoScrollGrace { return true }
        return false
    }
}
