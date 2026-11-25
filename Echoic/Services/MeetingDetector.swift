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
/// a call begins and stopping it when the call ends.
///
/// A call start is offered on exactly one surface (call-detection handover §2):
/// the floating prompt panel when the menu is closed, or the menu's on-a-call
/// state when it is open. See `CallPromptRouter`. Stopping (when auto-stop is
/// off) is still offered as a system notification.
@MainActor
final class MeetingDetector: ObservableObject {
    static let shared = MeetingDetector()

    static let settingsKey = "detectMeetings"
    static let autoStopSettingsKey = "autoStopRecordingWhenCallEnds"

    enum NotificationIds {
        static let stopCategory = "MEETING_ENDED"
        static let stopAction = "STOP_RECORDING"
        static let dismissAction = "DISMISS"
        static let stopRequest = "meeting-ended"
        static let autoStopRequest = "recording-auto-stopped"
        /// Posted by builds before the call prompt panel; removed on launch.
        static let legacyStartRequest = "meeting-detected"
    }

    /// The prompt currently being offered, if any.
    @Published private(set) var prompt: MeetingPrompt?

    private var startPolicy = MeetingDetectionPolicy(minimumActiveDuration: 5)
    private var router = CallPromptRouter()
    private let panel: CallPromptPresenting
    private var endPolicy = MeetingEndDetectionPolicy(minimumInactiveDuration: 10)
    /// Most recent app seen using the mic during the current recording.
    private var recordingAppName: String?
    private var monitorTask: Task<Void, Never>?
    private static let pollInterval: UInt64 = 2_000_000_000 // 2s

    private init(panel: CallPromptPresenting = CallPromptPanelController.shared) {
        self.panel = panel
    }

    /// Whether detection is enabled in Settings (on by default).
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingsKey) as? Bool ?? true
    }

    func start() {
        guard monitorTask == nil else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [NotificationIds.legacyStartRequest])
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

    /// Whether recording stops on its own when the call ends, instead of
    /// asking (on by default). Only applies while detection is enabled.
    nonisolated static func isAutoStopEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: autoStopSettingsKey) as? Bool ?? true
    }

    /// The app on the call while a start prompt is up ("You're on a Zoom call").
    var callAppName: String? {
        if case .start(let usage) = prompt { return usage.appName }
        return nil
    }

    /// Whether a call is detected and waiting for an answer (menu shows its on-a-call state).
    var isOnUnansweredCall: Bool {
        if case .start = prompt { return true }
        return false
    }

    // MARK: - Menu

    /// The menu bar popover opened: it takes over from the prompt panel.
    func menuOpened() {
        perform(router.menuOpened())
    }

    /// The menu closed. Closing it without recording declines the call.
    func menuClosed() {
        perform(router.menuClosed())
    }

    private func perform(_ effects: [CallPromptRouter.Effect]) {
        for effect in effects {
            switch effect {
            case .showPanel:
                let text = CallPromptRouter.promptText(appName: callAppName)
                panel.show(
                    title: text.title, subtitle: text.subtitle,
                    onRecord: { [weak self] in self?.acceptPrompt() },
                    onClose: { [weak self] in self?.dismissPrompt() }
                )
            case .hidePanel:
                panel.hide()
            case .decline:
                dismissPrompt()
            }
        }
    }

    // MARK: - User Responses

    /// Performs the prompt's action (start or stop recording).
    func acceptPrompt() {
        guard let current = prompt else { return }
        hidePrompt()
        let coordinator = MeetingCoordinator.shared
        switch current {
        case .start:
            // Same start action as every other Start control, using the ticked sources.
            coordinator.databaseWriter = DatabaseManager.shared.databaseWriter
            Task { await coordinator.startRecording() }
        case .stop:
            Task { await coordinator.stopRecording() }
        }
    }

    /// Dismisses the prompt without acting ("Not now" / "Keep Recording").
    /// A dismissed start prompt doesn't come back for this call.
    func dismissPrompt() {
        if case .start = prompt {
            // Model was preloaded for this prompt; let it unload if unused
            MeetingCoordinator.shared.scheduleModelUnload()
        }
        hidePrompt()
    }

    /// Handles a notification button press. Ignores stale notifications whose
    /// category no longer matches the visible prompt.
    func handleNotificationResponse(category: String, action: String) {
        guard case .stop = prompt, category == NotificationIds.stopCategory else { return }

        switch action {
        case NotificationIds.stopAction:
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
            recordingAppName = name
        } else if !isRecording {
            recordingAppName = nil
        }

        apply(startPolicy.update(micInUse: usage.isInUse, canRecord: canRecord, now: now),
              prompt: .start(usage))
        apply(endPolicy.update(micInUse: usage.isInUse, isRecording: isRecording, now: now),
              prompt: .stop(appName: recordingAppName))
    }

    private func apply(_ action: MeetingDetectionPolicy.Action, prompt newPrompt: MeetingPrompt) {
        switch action {
        case .prompt:
            if case .stop(let appName) = newPrompt, Self.isAutoStopEnabled() {
                autoStop(appName: appName)
                return
            }
            logger.info("Showing meeting prompt: \(String(describing: newPrompt), privacy: .public)")
            prompt = newPrompt
            if case .start = newPrompt {
                // Warm the model now so recording starts transcribing immediately
                Task { try? await MeetingCoordinator.shared.prepareTranscriptionModel() }
                perform(router.callDetected())
            } else {
                Task { await postNotification(for: newPrompt) }
            }
        case .dismissPrompt:
            // The call ended (or recording started elsewhere): the prompt goes away.
            if prompt?.kind == newPrompt.kind {
                prompt = nil
            }
            if newPrompt.kind == .start {
                perform(router.promptEnded())
            }
            if newPrompt.kind == .start, MeetingCoordinator.shared.state != .recording {
                // Call ended without recording; release the preloaded model later
                MeetingCoordinator.shared.scheduleModelUnload()
            }
            removeNotification(for: newPrompt)
        case .none:
            break
        }
    }

    /// The call ended: stop recording without asking, and say so.
    private func autoStop(appName: String?) {
        logger.info("Call ended; stopping recording automatically")
        endPolicy.promptHandled()
        Task {
            await MeetingCoordinator.shared.stopRecording()
            let text = Self.autoStopNotificationText(appName: appName)
            await postNotification(title: text.title, body: text.body, requestId: NotificationIds.autoStopRequest)
        }
    }

    private func hidePrompt() {
        guard let current = prompt else { return }
        prompt = nil
        switch current {
        case .start:
            startPolicy.promptHandled()
            perform(router.promptEnded())
        case .stop:
            endPolicy.promptHandled()
            removeNotification(for: current)
        }
    }

    // MARK: - Notifications

    /// Only stop prompts use notifications; start prompts use the panel or the menu.
    private func postNotification(for prompt: MeetingPrompt) async {
        guard case .stop(let appName) = prompt else { return }
        let text = Self.stopNotificationText(appName: appName)
        await postNotification(title: text.title, body: text.body, requestId: NotificationIds.stopRequest,
                               category: NotificationIds.stopCategory)
    }

    private func postNotification(title: String, body: String, requestId: String, category: String? = nil) async {
        let center = UNUserNotificationCenter.current()
        // No-op after the first time; asks for permission on first detection.
        _ = try? await center.requestAuthorization(options: [.alert, .sound])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category {
            content.categoryIdentifier = category
        }

        let request = UNNotificationRequest(identifier: requestId, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            logger.error("Failed to post meeting notification: \(error.localizedDescription)")
        }
    }

    /// Stop notification wording. Names Echoic explicitly, since the banner may
    /// not otherwise make clear which app is asking.
    nonisolated static func stopNotificationText(appName: String?) -> (title: String, body: String) {
        let what = appName.map { "\($0) stopped using your microphone." }
            ?? "Your microphone is no longer in use."
        return ("Meeting ended?", "\(what) Should Echoic stop recording?")
    }

    nonisolated static func autoStopNotificationText(appName: String?) -> (title: String, body: String) {
        let what = appName.map { "\($0) stopped using your microphone, so" } ?? "Your call ended, so"
        return ("Recording stopped", "\(what) Echoic stopped recording.")
    }

    private func removeNotification(for prompt: MeetingPrompt) {
        guard prompt.kind == .stop else { return }
        let id = NotificationIds.stopRequest
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    /// Registers notification categories with their action buttons.
    static func registerNotificationCategories() {
        let stopCategory = UNNotificationCategory(
            identifier: NotificationIds.stopCategory,
            actions: [
                UNNotificationAction(identifier: NotificationIds.stopAction, title: "Stop Recording", options: []),
                UNNotificationAction(identifier: NotificationIds.dismissAction, title: "Keep Recording", options: []),
            ],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([stopCategory])
    }

    /// Whether a notification category belongs to the meeting detector.
    nonisolated static func handles(category: String) -> Bool {
        category == NotificationIds.stopCategory
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
