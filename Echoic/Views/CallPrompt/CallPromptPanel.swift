import AppKit
import SwiftUI

/// Shows and hides the call prompt panel.
@MainActor
protocol CallPromptPresenting: AnyObject {
    func show(title: String, subtitle: String, onRecord: @escaping () -> Void, onClose: @escaping () -> Void)
    func hide()
}

/// A floating, non-activating panel owned by Echoic, placed top right under the
/// menu bar where system notifications appear. It never takes focus from the
/// call app. AppKit is needed here: SwiftUI on macOS 13 has no floating panels.
@MainActor
final class CallPromptPanelController: CallPromptPresenting {
    static let shared = CallPromptPanelController()

    private var panel: NSPanel?
    /// Room around the card for its shadow.
    private static let shadowMargin: CGFloat = 32
    /// Gap between the card and the screen's top-right corner.
    private static let screenInset: CGFloat = 12

    func show(title: String, subtitle: String, onRecord: @escaping () -> Void, onClose: @escaping () -> Void) {
        let view = CallPromptView(title: title, subtitle: subtitle, onRecord: onRecord, onClose: onClose)
            .padding(Self.shadowMargin)
        let panel = self.panel ?? Self.makePanel()
        panel.contentView = NSHostingView(rootView: view)
        panel.setFrame(Self.frame(), display: true)
        panel.setAccessibilityLabel("Call detected")
        panel.orderFrontRegardless()
        self.panel = panel

        NSAccessibility.post(
            element: panel,
            notification: .announcementRequested,
            userInfo: [.announcement: "Call detected. \(title). \(subtitle)", .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: frame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // drawn by SwiftUI to match the spec
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.setAccessibilitySubrole(.dialog)
        return panel
    }

    /// Top right of the screen with the menu bar.
    private static func frame() -> NSRect {
        let size = NSSize(
            width: CallPromptView.size.width + shadowMargin * 2,
            height: CallPromptView.size.height + shadowMargin * 2
        )
        let visible = (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: visible.maxX - screenInset - CallPromptView.size.width - shadowMargin,
            y: visible.maxY - screenInset - CallPromptView.size.height - shadowMargin,
            width: size.width,
            height: size.height
        )
    }
}
