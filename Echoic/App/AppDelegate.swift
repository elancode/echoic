import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        // Request screen capture access so the app appears in System Settings
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running as menu bar app even when all windows are closed
        return false
    }

    func applicationDidResignActive(_ notification: Notification) {
        // Revert to menu-bar-only when no windows are visible
        let hasVisibleWindows = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        if !hasVisibleWindows {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

enum RecordingState: String {
    case idle
    case recording
    case processing
}
