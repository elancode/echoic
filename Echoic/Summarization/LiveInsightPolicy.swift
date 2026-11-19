import Foundation

/// Pure decision logic for "should the live insights agent look at the transcript now?".
///
/// Runs once enough new speech has accumulated, or earlier when a moderate amount
/// of speech is followed by a pause (a natural topic break). Never runs while a
/// request is in flight or within the cooldown after the previous run. A manual
/// refresh skips the thresholds and cooldown but still needs some new speech.
struct LiveInsightPolicy {
    var minimumNewSpeechMs: Int64 = 90_000
    var pauseTriggerSpeechMs: Int64 = 45_000
    var pauseDuration: TimeInterval = 8
    var cooldown: TimeInterval = 90

    /// - Parameters:
    ///   - newSpeechMs: Total duration of transcript not yet seen by the agent.
    ///   - secondsSinceLastSegment: Wall-clock time since the last transcript segment arrived.
    ///   - secondsSinceLastRun: Wall-clock time since the previous run, or `nil` if none yet.
    ///   - inFlight: Whether a request is currently running.
    ///   - manual: Whether the user asked for a refresh.
    func shouldRun(
        newSpeechMs: Int64,
        secondsSinceLastSegment: TimeInterval,
        secondsSinceLastRun: TimeInterval?,
        inFlight: Bool,
        manual: Bool
    ) -> Bool {
        guard !inFlight, newSpeechMs > 0 else { return false }
        if manual { return true }

        if let secondsSinceLastRun, secondsSinceLastRun < cooldown {
            return false
        }

        if newSpeechMs >= minimumNewSpeechMs { return true }
        return newSpeechMs >= pauseTriggerSpeechMs && secondsSinceLastSegment >= pauseDuration
    }
}
