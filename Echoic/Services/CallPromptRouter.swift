import Foundation

/// Decides where a "call started" prompt appears (call-detection handover §2):
/// one Start control per surface, and only one surface asks at a time.
///
/// - Menu closed: the floating prompt panel asks.
/// - Menu open: no panel; the menu switches to its on-a-call state.
/// - Opening the menu while the panel shows hides the panel.
/// - Closing the menu without recording is the decline.
struct CallPromptRouter {
    enum Effect: Equatable {
        case showPanel
        case hidePanel
        /// Treat the call as declined ("Not now") for this call.
        case decline
    }

    private(set) var isMenuOpen = false
    private(set) var isPanelVisible = false
    /// A call is detected and the user hasn't recorded or declined yet.
    private(set) var isCallUnanswered = false

    mutating func callDetected() -> [Effect] {
        isCallUnanswered = true
        guard !isMenuOpen else { return [] }
        isPanelVisible = true
        return [.showPanel]
    }

    mutating func menuOpened() -> [Effect] {
        isMenuOpen = true
        return hidePanelIfVisible()
    }

    mutating func menuClosed() -> [Effect] {
        isMenuOpen = false
        return isCallUnanswered ? [.decline] : []
    }

    /// The prompt ended: the user recorded or declined, or the call ended.
    mutating func promptEnded() -> [Effect] {
        isCallUnanswered = false
        return hidePanelIfVisible()
    }

    private mutating func hidePanelIfVisible() -> [Effect] {
        guard isPanelVisible else { return [] }
        isPanelVisible = false
        return [.hidePanel]
    }

    // MARK: - Copy

    /// Prompt panel title and subtitle ("Zoom call started" / "Record it with Echoic?").
    static func promptText(appName: String?) -> (title: String, subtitle: String) {
        let title = cleaned(appName).map { "\($0) call started" } ?? "Call started"
        return (title, "Record it with Echoic?")
    }

    /// Status line in the on-a-call menu.
    static func menuStatus(appName: String?) -> String {
        cleaned(appName).map { "You're on a \($0) call" } ?? "You're on a call"
    }

    private static func cleaned(_ appName: String?) -> String? {
        guard let name = appName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        return name
    }
}
