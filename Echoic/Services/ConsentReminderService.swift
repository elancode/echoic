import Foundation
import UserNotifications

/// Shows a recording consent reminder before/during recording.
enum ConsentReminderService {
    /// Shows a notification reminding the user to inform meeting participants.
    static func showReminder() {
        guard UserDefaults.standard.bool(forKey: "showConsentReminder") else { return }

        let content = UNMutableNotificationContent()
        content.title = "Recording Started"
        content.body = "Remember to inform meeting participants that this meeting is being recorded."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "recording-consent-\(UUID().uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Requests notification permission.
    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }
}
