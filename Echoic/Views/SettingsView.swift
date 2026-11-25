import AVFoundation
import CoreAudio
import CoreGraphics
import SwiftUI

struct SettingsView: View {
    enum Page: String, CaseIterable, Hashable {
        case general = "General"
        case api = "Claude"
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
        case .api: ClaudeProviderSettingsTab()
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

/// Settings > Claude: where summaries and live insights are sent.
struct ClaudeProviderSettingsTab: View {
    @AppStorage(ClaudeProviderSettings.kindKey) private var kind = ClaudeProviderKind.anthropic.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Provider") {
                HStack(spacing: 4) {
                    ForEach(ClaudeProviderKind.allCases, id: \.self) { option in
                        FilterPill(title: option.displayName, isSelected: option.rawValue == kind) {
                            kind = option.rawValue
                        }
                    }
                }
                Caption("Only transcript text is sent to Claude, for summaries and live insights. Audio never leaves this Mac.")
            }
            if kind == ClaudeProviderKind.bedrock.rawValue {
                BedrockSettings()
            } else {
                APISettingsTab()
            }
        }
    }
}

/// Amazon Bedrock: region and credentials, with a connection test.
private struct BedrockSettings: View {
    @AppStorage(ClaudeProviderSettings.bedrockRegionKey) private var region = ClaudeProviderSettings.defaultRegion
    @AppStorage(ClaudeProviderSettings.bedrockAuthKey) private var auth = BedrockAuthMode.awsProfile.rawValue
    @AppStorage(ClaudeProviderSettings.bedrockProfileKey) private var profile = ClaudeProviderSettings.defaultProfile
    @State private var apiKeyDraft = ""
    @State private var hasAPIKey = false
    @State private var test: ConnectionTest = .idle

    enum ConnectionTest: Equatable {
        case idle, testing, success(String), failure(String)
    }

    var body: some View {
        SettingsSection(title: "Amazon Bedrock") {
            LabeledField(label: "Region") {
                TextField("us-east-1", text: $region).textFieldStyle(.plain).font(.mono(12))
            }
            HStack(spacing: 4) {
                ForEach(BedrockAuthMode.allCases, id: \.self) { mode in
                    FilterPill(title: mode.displayName, isSelected: mode.rawValue == auth) { auth = mode.rawValue }
                }
            }
            if auth == BedrockAuthMode.apiKey.rawValue {
                apiKeyFields
            } else {
                LabeledField(label: "Profile") {
                    TextField("default", text: $profile).textFieldStyle(.plain).font(.mono(12))
                }
                Caption("Uses this profile from ~/.aws/config, including SSO and credential_process helpers. "
                        + "Echoic doesn't store AWS credentials.")
            }
            HStack(spacing: 8) {
                Button(test == .testing ? "Testing…" : "Test connection", action: runTest)
                    .buttonStyle(InkButtonStyle(kind: .secondary))
                    .disabled(test == .testing)
                testResult
            }
        }
        .onAppear { hasAPIKey = (try? KeychainService.retrieveBedrockAPIKey()) != nil }
        .onChange(of: region) { _ in test = .idle }
        .onChange(of: auth) { _ in test = .idle }
        .onChange(of: profile) { _ in test = .idle }
    }

    @ViewBuilder
    private var apiKeyFields: some View {
        if hasAPIKey {
            HStack {
                StatusText(text: "Bedrock API key saved in Keychain", isGood: true)
                Spacer()
                Button("Remove") {
                    try? KeychainService.deleteBedrockAPIKey()
                    hasAPIKey = false
                }
                .buttonStyle(InkButtonStyle(kind: .secondary))
            }
        } else {
            HStack(spacing: 8) {
                LabeledField(label: "API key") {
                    SecureField("Bedrock API key", text: $apiKeyDraft).textFieldStyle(.plain).font(.mono(12))
                }
                Button("Save") {
                    try? KeychainService.saveBedrockAPIKey(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                    apiKeyDraft = ""
                    hasAPIKey = true
                }
                .buttonStyle(InkButtonStyle(kind: .primary))
                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        Caption("Short-term keys last up to 12 hours and work only in the region they were created in.")
    }

    @ViewBuilder
    private var testResult: some View {
        switch test {
        case .success(let model): StatusText(text: "Connected · \(model)", isGood: true)
        case .failure(let message): StatusText(text: message, isGood: false)
        case .idle, .testing: EmptyView()
        }
    }

    /// Lists models with the current settings: proves credentials, region and access.
    private func runTest() {
        test = .testing
        let provider = ClaudeProviders.current()
        Task {
            do {
                var model = try await provider.newestModel(in: "opus")
                if model == nil { model = try await provider.newestModel(in: "sonnet") }
                if let model {
                    test = .success(model)
                } else {
                    test = .failure("Connected, but no Claude models are enabled in \(region).")
                }
            } catch {
                test = .failure(Self.describe(error))
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case AnthropicError.httpError(let status, _) where status == 401 || status == 403:
            return "Access denied. Check the credentials and that this account can use Bedrock here."
        case AnthropicError.invalidURL:
            return "That region doesn't look right."
        case KeychainService.KeychainError.itemNotFound:
            return "Save a Bedrock API key first."
        default:
            return error.localizedDescription
        }
    }
}

/// A label beside a bordered single-line field.
private struct LabeledField<Field: View>: View {
    let label: String
    @ViewBuilder let field: Field

    var body: some View {
        HStack(spacing: 12) {
            Text(label).frame(width: 64, alignment: .leading)
            field
                .padding(.horizontal, 10)
                .frame(height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )
        }
    }
}

struct APISettingsTab: View {
    @State private var apiKey = ""
    @State private var hasExistingKey = false
    @State private var validationState: ValidationState = .idle
    @State private var showDeleteConfirmation = false

    enum ValidationState {
        case idle, validating, valid, invalid
    }

    var body: some View {
        SettingsSection(title: "Anthropic API key") {
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
