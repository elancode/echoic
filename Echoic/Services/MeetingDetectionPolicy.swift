import Foundation

/// Pure decision logic for "a meeting seems to be starting — offer to record?".
///
/// A "mic session" begins when another app starts using the microphone and ends
/// when it releases it. We prompt at most once per session, only after the mic
/// has been continuously active for `minimumActiveDuration` (filters out brief
/// blips like dictation), and never while Echoic is already recording.
struct MeetingDetectionPolicy {
    enum Action: Equatable {
        case none
        case prompt
        case dismissPrompt
    }

    let minimumActiveDuration: TimeInterval

    private(set) var isPromptVisible = false
    private var activeSince: Date?
    /// True once we've prompted (or seen a recording) during the current mic session.
    private var sessionHandled = false

    init(minimumActiveDuration: TimeInterval = 5) {
        self.minimumActiveDuration = minimumActiveDuration
    }

    /// Feeds the latest observation and returns what the UI should do.
    /// - Parameters:
    ///   - micInUse: Whether another app is currently capturing from a microphone.
    ///   - canRecord: Whether Echoic is idle and able to start a recording.
    mutating func update(micInUse: Bool, canRecord: Bool, now: Date) -> Action {
        guard micInUse else {
            activeSince = nil
            sessionHandled = false
            return hidePromptIfVisible()
        }

        let sessionStart = activeSince ?? now
        activeSince = sessionStart

        guard canRecord else {
            // Already recording (or processing) — this call is covered.
            sessionHandled = true
            return hidePromptIfVisible()
        }

        guard !sessionHandled,
              now.timeIntervalSince(sessionStart) >= minimumActiveDuration else {
            return .none
        }

        sessionHandled = true
        isPromptVisible = true
        return .prompt
    }

    /// Call when the user accepts or dismisses the prompt.
    mutating func promptHandled() {
        isPromptVisible = false
    }

    private mutating func hidePromptIfVisible() -> Action {
        guard isPromptVisible else { return .none }
        isPromptVisible = false
        return .dismissPrompt
    }
}
