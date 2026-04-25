import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        // Do NOT check screen capture permission here — both
        // CGRequestScreenCaptureAccess() and SCShareableContent can trigger
        // system dialogs that restart the app in a loop. Permission is checked
        // only when the user clicks "Start Recording".

        // Stop recording gracefully when the system sleeps (e.g. laptop lid close)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
    }

    @objc private func handleSleep(_ notification: Notification) {
        Task { @MainActor in
            let coordinator = MeetingCoordinator.shared
            guard coordinator.state == .recording else { return }
            await coordinator.stopRecording()
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
