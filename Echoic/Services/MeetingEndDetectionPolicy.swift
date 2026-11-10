import Foundation

/// Pure decision logic for "the call seems to have ended — stop recording?".
///
/// Only arms once another app has used the microphone during the current
/// recording (so non-call recordings are never interrupted). Prompts after the
/// mic has been released for `minimumInactiveDuration` (tolerates brief drops
/// such as reconnects or device switches). After the user keeps recording, it
/// re-arms only when the mic is used again.
struct MeetingEndDetectionPolicy {
    typealias Action = MeetingDetectionPolicy.Action

    let minimumInactiveDuration: TimeInterval

    private(set) var isPromptVisible = false
    private var sawMicInUse = false
    private var inactiveSince: Date?

    init(minimumInactiveDuration: TimeInterval = 10) {
        self.minimumInactiveDuration = minimumInactiveDuration
    }

    /// Feeds the latest observation and returns what the UI should do.
    /// - Parameters:
    ///   - micInUse: Whether another app is currently capturing from a microphone.
    ///   - isRecording: Whether Echoic is currently recording.
    mutating func update(micInUse: Bool, isRecording: Bool, now: Date) -> Action {
        guard isRecording else {
            sawMicInUse = false
            inactiveSince = nil
            return hidePromptIfVisible()
        }

        if micInUse {
            // Call is (still or again) active.
            sawMicInUse = true
            inactiveSince = nil
            return hidePromptIfVisible()
        }

        guard sawMicInUse else { return .none }

        let releasedAt = inactiveSince ?? now
        inactiveSince = releasedAt

        guard now.timeIntervalSince(releasedAt) >= minimumInactiveDuration else { return .none }

        sawMicInUse = false
        isPromptVisible = true
        return .prompt
    }

    /// Call when the user stops or keeps recording from the prompt.
    mutating func promptHandled() {
        isPromptVisible = false
    }

    private mutating func hidePromptIfVisible() -> Action {
        guard isPromptVisible else { return .none }
        isPromptVisible = false
        return .dismissPrompt
    }
}
