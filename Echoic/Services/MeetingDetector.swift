import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.echoic.app", category: "MeetingDetector")

/// A prompt offered to the user based on microphone activity.
enum MeetingPrompt: Equatable {
    /// A call seems to have started — offer to start recording.
    case start(MicrophoneUsage)
    /// The call app released the mic — offer to stop recording.
    case stop(appName: String?)
}

/// Watches microphone activity by other apps to offer starting a recording when
/// a call begins and stopping it when the call ends — via a notification with
/// action buttons and a prompt row in the menu bar popover.
@MainActor
final class MeetingDetector: ObservableObject {
    static let shared = MeetingDetector()

    static let settingsKey = "detectMeetings"

    enum NotificationIds {
        static let startCategory = "MEETING_DETECTED"
        static let stopCategory = "MEETING_ENDED"
        static let startAction = "START_RECORDING"
        static let stopAction = "STOP_RECORDING"
        static let dismissAction = "DISMISS"
        static let startRequest = "meeting-detected"
        static let stopRequest = "meeting-ended"
    }

    /// The prompt currently being offered, if any.
    @Published private(set) var prompt: MeetingPrompt?

    private var startPolicy = MeetingDetectionPolicy(minimumActiveDuration: 5)
    private var endPolicy = MeetingEndDetectionPolicy(minimumInactiveDuration: 10)
    /// Most recent app seen using the mic during the current recording.
    private var callAppName: String?
    private var monitorTask: Task<Void, Never>?
    private static let pollInterval: UInt64 = 2_000_000_000 // 2s

    private init() {}

    /// Whether detection is enabled in Settings (on by default).
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingsKey) as? Bool ?? true
    }

    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: Self.pollInterval)
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: - User Responses

    /// Performs the prompt's action (start or stop recording).
    func acceptPrompt() {
        guard let current = prompt else { return }
        hidePrompt()
        let coordinator = MeetingCoordinator.shared
        switch current {
        case .start:
            coordinator.databaseWriter = DatabaseManager.shared.databaseWriter
            Task { await coordinator.startRecording() }
        case .stop:
            Task { await coordinator.stopRecording() }
        }
    }

    /// Dismisses the prompt without acting ("Not Now" / "Keep Recording").
    func dismissPrompt() {
        hidePrompt()
    }

    /// Handles a notification button press. Ignores stale notifications whose
    /// category no longer matches the visible prompt.
    func handleNotificationResponse(category: String, action: String) {
        guard let current = prompt else { return }
        let expectedCategory = current.kind == .start ? NotificationIds.startCategory : NotificationIds.stopCategory
        guard category == expectedCategory else { return }

        switch action {
        case NotificationIds.startAction, NotificationIds.stopAction:
            acceptPrompt()
        case NotificationIds.dismissAction, UNNotificationDismissActionIdentifier:
            dismissPrompt()
        default:
            // Clicking the banner body leaves the prompt in the menu bar popover.
            break
        }
    }

    // MARK: - Polling

    private func poll() async {
        let usage: MicrophoneUsage
        if Self.isEnabled {
            usage = await Task.detached(priority: .utility) {
                MicrophoneActivityMonitor.currentUsage()
            }.value
        } else {
            usage = .idle
        }

        let state = MeetingCoordinator.shared.state
        let canRecord = state == .idle || state.errorText != nil
        let isRecording = state == .recording
        let now = Date()

        if isRecording, usage.isInUse, let name = usage.appName {
            callAppName = name
        } else if !isRecording {
            callAppName = nil
        }

        apply(startPolicy.update(micInUse: usage.isInUse, canRecord: canRecord, now: now),
              prompt: .start(usage))
        apply(endPolicy.update(micInUse: usage.isInUse, isRecording: isRecording, now: now),
              prompt: .stop(appName: callAppName))
    }

    private func apply(_ action: MeetingDetectionPolicy.Action, prompt newPrompt: MeetingPrompt) {
        switch action {
        case .prompt:
            logger.info("Showing meeting prompt: \(String(describing: newPrompt), privacy: .public)")
            prompt = newPrompt
            Task { await postNotification(for: newPrompt) }
        case .dismissPrompt:
            if prompt?.kind == newPrompt.kind {
                prompt = nil
            }
            removeNotification(for: newPrompt)
        case .none:
            break
        }
    }

    private func hidePrompt() {
        guard let current = prompt else { return }
        switch current {
        case .start: startPolicy.promptHandled()
        case .stop: endPolicy.promptHandled()
        }
        prompt = nil
        removeNotification(for: current)
    }

    // MARK: - Notifications

    private func postNotification(for prompt: MeetingPrompt) async {
        let center = UNUserNotificationCenter.current()
        // No-op after the first time; asks for permission on first detection.
        _ = try? await center.requestAuthorization(options: [.alert, .sound])

        let content = UNMutableNotificationContent()
        content.sound = .default
        let requestId: String

        switch prompt {
        case .start(let usage):
            content.title = "Meeting detected"
            content.body = usage.appName.map { "\($0) is using your microphone. Start recording this meeting?" }
                ?? "Your microphone is in use. Start recording this meeting?"
            content.categoryIdentifier = NotificationIds.startCategory
            requestId = NotificationIds.startRequest
        case .stop(let appName):
            content.title = "Meeting ended?"
            content.body = appName.map { "\($0) stopped using your microphone. Stop recording?" }
                ?? "Your microphone is no longer in use. Stop recording?"
            content.categoryIdentifier = NotificationIds.stopCategory
            requestId = NotificationIds.stopRequest
        }

        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            logger.error("Failed to post meeting notification: \(error.localizedDescription)")
        }
    }

    private func removeNotification(for prompt: MeetingPrompt) {
        let id = prompt.kind == .start ? NotificationIds.startRequest : NotificationIds.stopRequest
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Registers notification categories with their action buttons.
    static func registerNotificationCategories() {
        let dismissStart = UNNotificationAction(identifier: NotificationIds.dismissAction, title: "Not Now", options: [])
        let startCategory = UNNotificationCategory(
            identifier: NotificationIds.startCategory,
            actions: [
                UNNotificationAction(identifier: NotificationIds.startAction, title: "Start Recording", options: []),
                dismissStart,
            ],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let stopCategory = UNNotificationCategory(
            identifier: NotificationIds.stopCategory,
            actions: [
                UNNotificationAction(identifier: NotificationIds.stopAction, title: "Stop Recording", options: []),
                UNNotificationAction(identifier: NotificationIds.dismissAction, title: "Keep Recording", options: []),
            ],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([startCategory, stopCategory])
    }

    /// Whether a notification category belongs to the meeting detector.
    nonisolated static func handles(category: String) -> Bool {
        category == NotificationIds.startCategory || category == NotificationIds.stopCategory
    }
}

private extension MeetingPrompt {
    enum Kind { case start, stop }

    var kind: Kind {
        switch self {
        case .start: return .start
        case .stop: return .stop
        }
    }
}
