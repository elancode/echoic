import AVFoundation
import CoreAudio
import CoreGraphics
import SwiftUI

struct SettingsView: View {
    enum Page: String, CaseIterable, Hashable {
        case general = "General"
        case api = "API key"
        case audio = "Audio"
        case models = "Models"
    }

    @State private var page: Page = .audio

    var body: some View {
        HStack(spacing: 0) {
            SettingsNav(selection: $page)
                .frame(width: 168)
            Rectangle().fill(Theme.borderSoft).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(page.rawValue)
                        .font(.display(18))
                        .foregroundColor(Theme.ink)
                        .padding(.bottom, 18)
                    pageContent
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.surface)
        }
        .font(.inter(13))
        .foregroundColor(Theme.ink)
        .toggleStyle(InkCheckboxStyle())
        .background(Theme.ground.ignoresSafeArea())
        .preferredColorScheme(.light)
        .frame(width: 640, height: 560)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .general: GeneralSettingsTab()
        case .api: APISettingsTab()
        case .audio: AudioSettingsTab()
        case .models: ModelSettingsTab()
        }
    }
}

/// Left nav; the selected item is an ink pill.
private struct SettingsNav: View {
    @Binding var selection: SettingsView.Page

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsView.Page.allCases, id: \.self) { page in
                let isSelected = page == selection
                Button { selection = page } label: {
                    Text(page.rawValue)
                        .font(.inter(13, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? .white : Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(isSelected ? Theme.ink : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.ground)
    }
}

/// Section title over a card (Settings pages).
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GroupLabel(title)
            VStack(alignment: .leading, spacing: 14) { content }.inkCard()
        }
        .padding(.bottom, 20)
    }
}

/// Small explanatory text under a control.
private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.inter(12))
            .foregroundColor(Theme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showConsentReminder") private var showConsentReminder = true
    @AppStorage(MeetingDetector.settingsKey) private var detectMeetings = true
    @AppStorage(MeetingDetector.autoStopSettingsKey) private var autoStopRecording = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Recording") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Show recording consent reminder", isOn: $showConsentReminder)
                Toggle(isOn: $detectMeetings) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Offer to start and stop recording with meetings")
                        Caption("Prompts when another app starts or stops using your microphone.")
                    }
                }
                Toggle(isOn: $autoStopRecording) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stop recording automatically when the call ends")
                        Caption("Stops about 10 seconds after the call app releases your microphone, instead of asking.")
                    }
                }
                .padding(.leading, 26)
                .disabled(!detectMeetings)
            }
            SettingsSection(title: "Storage") {
                Text("~/Library/Application Support/Echoic/")
                    .font(.mono(12))
                    .foregroundColor(Theme.textSecondary)
                    .textSelection(.enabled)
                HStack(alignment: .top) {
                    Caption("Meetings are standard files: an SQLite database and AAC audio. They stay on this Mac.")
                    Spacer(minLength: 12)
                    Button("Reveal in Finder") {
                        if let url = try? AudioFileManager.baseURL() { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(InkButtonStyle(kind: .secondary))
                }
            }
            Text("Echoic \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
                .font(.mono(11))
                .foregroundColor(Theme.textMuted)
        }
    }
}

// MARK: - API

struct APISettingsTab: View {
    @State private var apiKey = ""
    @State private var hasExistingKey = false
    @State private var validationState: ValidationState = .idle
    @State private var showDeleteConfirmation = false

    enum ValidationState {
        case idle, validating, valid, invalid
    }

    var body: some View {
        SettingsSection(title: "Anthropic") {
            if hasExistingKey {
                HStack(spacing: 8) {
                    StatusText(text: "Saved in Keychain", isGood: true)
                    Spacer()
                    Button("Remove") { showDeleteConfirmation = true }
                        .buttonStyle(InkButtonStyle(kind: .secondary))
                }
            } else {
                HStack(spacing: 8) {
                    SecureField("sk-ant-...", text: $apiKey)
                        .textFieldStyle(.plain)
                        .font(.mono(12))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .strokeBorder(Theme.border, lineWidth: 1)
                        )
                        .accessibilityLabel("Anthropic API key")
                    Button(validationState == .validating ? "Checking…" : "Save", action: saveAPIKey)
                        .buttonStyle(InkButtonStyle(kind: .primary))
                        .disabled(apiKey.isEmpty || validationState == .validating)
                }
                if validationState == .invalid {
                    StatusText(text: "That key didn't work. Check it and try again.", isGood: false)
                } else if validationState == .valid {
                    StatusText(text: "Key saved", isGood: true)
                }
            }
            Caption("Stored in the macOS Keychain, never written to disk. Used to summarize meetings; only transcript text is sent.")
        }
        .onAppear {
            hasExistingKey = (try? KeychainService.retrieveAPIKey()) != nil
        }
        .alert("Remove API key?", isPresented: $showDeleteConfirmation) {
            Button("Remove", role: .destructive) {
                try? KeychainService.deleteAPIKey()
                hasExistingKey = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("New meetings won't be summarized until you add a key.")
        }
    }

    private func saveAPIKey() {
        validationState = .validating
        Task {
            let client = AnthropicClient()
            let isValid = (try? await client.validateAPIKey(apiKey)) ?? false
            await MainActor.run {
                if isValid {
                    try? KeychainService.saveAPIKey(apiKey)
                    hasExistingKey = true
                    validationState = .valid
                    apiKey = ""
                } else {
                    validationState = .invalid
                }
            }
        }
    }
}

// MARK: - Audio

struct AudioSettingsTab: View {
    @AppStorage(MeetingCoordinator.microphoneSettingKey) private var enableMicrophone = true
    @State private var inputDevices: [(id: AudioDeviceID, name: String)] = []
    @State private var selectedDevice: AudioDeviceID?
    @State private var screenCaptureGranted = false
    @State private var microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Permissions") {
                PermissionRow(
                    title: "System audio",
                    status: screenCaptureGranted ? .granted : .unconfirmed,
                    explanation: "macOS lists this under Screen Recording. Echoic only takes the audio, never the picture.",
                    settingsPane: "Privacy_ScreenCapture"
                )
                Rectangle().fill(Theme.hairline).frame(height: 1)
                PermissionRow(
                    title: "Microphone",
                    status: PermissionRow.Status(microphoneStatus),
                    explanation: nil,
                    settingsPane: "Privacy_Microphone"
                )
            }
            SettingsSection(title: "Your voice") {
                Toggle(isOn: $enableMicrophone) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Transcribe my microphone").font(.inter(13, weight: .medium))
                        Caption("System audio only contains the other participants. Turn this on to also transcribe "
                                + "your side of the call, labelled \"You\". Mic audio stays on this Mac and is never uploaded.")
                    }
                }
                if enableMicrophone {
                    HStack {
                        Text("Input device")
                        Spacer()
                        Picker("Input device", selection: $selectedDevice) {
                            Text("Default").tag(nil as AudioDeviceID?)
                            ForEach(inputDevices, id: \.id) { device in
                                Text(device.name).tag(device.id as AudioDeviceID?)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 240)
                    }
                }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        inputDevices = MicrophoneCaptureService.availableInputDevices()
        // Preflight can report false even when access is granted (see AudioCaptureService),
        // so a false result is shown as "not confirmed" rather than "denied".
        screenCaptureGranted = CGPreflightScreenCaptureAccess()
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
}

/// A permission with its current state and a way to change it.
private struct PermissionRow: View {
    enum Status {
        case granted, denied, notAsked, unconfirmed

        init(_ status: AVAuthorizationStatus) {
            switch status {
            case .authorized: self = .granted
            case .denied, .restricted: self = .denied
            default: self = .notAsked
            }
        }

        var text: String {
            switch self {
            case .granted: return "Granted"
            case .denied: return "Not allowed"
            case .notAsked: return "Asked on first recording"
            case .unconfirmed: return "Not confirmed"
            }
        }
    }

    let title: String
    let status: Status
    let explanation: String?
    let settingsPane: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.inter(13, weight: .medium))
                Spacer()
                StatusText(text: status.text, isGood: status == .granted)
            }
            if let explanation { Caption(explanation) }
            if status != .granted || explanation != nil {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsPane)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(InkButtonStyle(kind: .secondary))
                .padding(.top, 2)
            }
        }
    }
}

/// Status paired with text and an icon, so it never relies on colour alone.
private struct StatusText: View {
    let text: String
    let isGood: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isGood ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 11))
                .accessibilityHidden(true)
            Text(text).font(.inter(12, weight: .medium))
        }
        .foregroundColor(isGood ? Theme.success : Theme.accentText)
    }
}

// MARK: - Models

struct ModelSettingsTab: View {
    @ObservedObject private var modelManager = ModelDownloadManager.shared
    @AppStorage(AnthropicClient.summarizationModelKey) private var summarizationModel = AnthropicClient.defaultSummarizationModel
    @AppStorage(MeetingCoordinator.liveInsightsSettingKey) private var liveInsightsEnabled = true
    @AppStorage(AnthropicClient.liveInsightsModelKey) private var liveInsightsModel = AnthropicClient.defaultLiveInsightsModel

    private static let availableLiveInsightsModels = [
        ModelResolver.automatic("opus"),
        "claude-opus-5-5",
        "claude-sonnet-5-5",
    ]

    private static let availableSummarizationModels = [
        ModelResolver.automatic("opus"),
        "claude-opus-5-5",
        "claude-sonnet-5-5",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Transcription") {
                ForEach(modelManager.availableModels) { model in
                    TranscriptionModelRow(model: model, modelManager: modelManager)
                    if model.id != modelManager.availableModels.last?.id {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                    }
                }
                if !TranscriptionService.isAppleSilicon {
                    Caption("Intel Mac detected. Transcription runs in batch mode after meetings end.")
                }
            }
            SettingsSection(title: "Summarization") {
                Picker("Model", selection: $summarizationModel) {
                    ForEach(Self.availableSummarizationModels, id: \.self) { model in
                        Text(ModelResolver.displayName(for: model)).tag(model)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 280)
                Caption("Claude model used to generate meeting summaries.")
            }
            SettingsSection(title: "Live insights") {
                LiveInsightsSettings(
                    enabled: $liveInsightsEnabled,
                    model: $liveInsightsModel,
                    availableModels: Self.availableLiveInsightsModels
                )
            }
        }
    }
}

private struct TranscriptionModelRow: View {
    let model: ModelDownloadManager.ModelInfo
    @ObservedObject var modelManager: ModelDownloadManager

    var body: some View {
        HStack {
            Text(model.displayName)
            Spacer()
            if modelManager.downloadedModels.contains(where: { $0.name == model.name }) {
                StatusText(text: "Installed", isGood: true)
                Button("Delete") { try? modelManager.delete(model) }
                    .buttonStyle(InkButtonStyle(kind: .secondary, height: 28))
            } else if modelManager.isDownloading {
                ProgressView(value: modelManager.downloadProgress).frame(width: 100)
            } else {
                Button("Download") { Task { try? await modelManager.download(model) } }
                    .buttonStyle(InkButtonStyle(kind: .secondary, height: 28))
            }
        }
    }
}

private struct LiveInsightsSettings: View {
    @Binding var enabled: Bool
    @Binding var model: String
    let availableModels: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Live insights during meetings", isOn: $enabled)

            Picker("Model", selection: $model) {
                ForEach(availableModels, id: \.self) { model in
                    Text(ModelResolver.displayName(for: model)).tag(model)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 280)
            .disabled(!enabled)

            Caption("While recording, Claude reads the transcript text every minute or two and shows a recap, "
                    + "open concerns, and questions. Audio never leaves your Mac.")
        }
    }
}
