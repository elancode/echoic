import SwiftUI
import CoreAudio

struct SettingsView: View {
    private enum Tab: Hashable {
        case general, api, audio, models
    }

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(Tab.general)

            APISettingsTab()
                .tabItem { Label("API", systemImage: "key") }
                .tag(Tab.api)

            AudioSettingsTab()
                .tabItem { Label("Audio", systemImage: "waveform") }
                .tag(Tab.audio)

            ModelSettingsTab()
                .tabItem { Label("Models", systemImage: "cpu") }
                .tag(Tab.models)
        }
        .frame(width: 480, height: 300)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showConsentReminder") private var showConsentReminder = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Toggle("Show recording consent reminder", isOn: $showConsentReminder)
            }

            Divider()

            HStack {
                Text("Storage")
                    .fontWeight(.medium)
                Spacer()
                Text("~/Library/Application Support/Echoic/")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                Button("Reveal") {
                    if let url = try? AudioFileManager.baseURL() {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }

            Spacer()
        }
        .padding(20)
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Anthropic API Key")
                .fontWeight(.medium)

            if hasExistingKey {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Saved in Keychain")
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Remove", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 8) {
                    SecureField("sk-ant-...", text: $apiKey)

                    Button("Save") {
                        saveAPIKey()
                    }
                    .controlSize(.small)
                    .disabled(apiKey.isEmpty || validationState == .validating)

                    if validationState == .validating {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 16)
                    } else if validationState == .valid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if validationState == .invalid {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
            }

            Text("Stored in macOS Keychain. Never written to disk. Used for meeting summarization.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(20)
        .onAppear {
            hasExistingKey = (try? KeychainService.retrieveAPIKey()) != nil
        }
        .alert("Delete API Key?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                try? KeychainService.deleteAPIKey()
                hasExistingKey = false
            }
            Button("Cancel", role: .cancel) {}
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
    @AppStorage("enableMicrophone") private var enableMicrophone = false
    @State private var inputDevices: [(id: AudioDeviceID, name: String)] = []
    @State private var selectedDevice: AudioDeviceID?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Permissions")
                    .fontWeight(.medium)

                HStack {
                    Text("Screen Recording")
                    Spacer()
                    if AudioCaptureService.hasScreenCapturePermission() {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Button("Open System Settings") {
                            _ = AudioCaptureService.requestScreenCapturePermission()
                            // Also open System Settings directly as fallback
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                }

                Text("Required for capturing system audio. No video or screen content is captured.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Microphone")
                    .fontWeight(.medium)

                Toggle("Enable microphone for speaker identification", isOn: $enableMicrophone)

                if enableMicrophone {
                    Picker("Input Device", selection: $selectedDevice) {
                        Text("Default").tag(nil as AudioDeviceID?)
                        ForEach(inputDevices, id: \.id) { device in
                            Text(device.name).tag(device.id as AudioDeviceID?)
                        }
                    }
                    .frame(maxWidth: 300)
                }

                Text("Used to identify you as a speaker. Mic audio is never uploaded.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(20)
        .onAppear {
            inputDevices = MicrophoneCaptureService.availableInputDevices()
        }
    }
}

// MARK: - Models

struct ModelSettingsTab: View {
    @StateObject private var modelManager = ModelDownloadManager()
    @AppStorage("summarizationModel") private var summarizationModel = "claude-sonnet-4-6"

    private static let availableSummarizationModels = [
        "claude-sonnet-4-6",
        "claude-opus-4-6",
        "claude-haiku-4-5",
        "claude-3-5-sonnet-20241022",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription Models")
                .fontWeight(.medium)

            VStack(spacing: 8) {
                ForEach(modelManager.availableModels) { model in
                    HStack {
                        Text(model.displayName)

                        Spacer()

                        if modelManager.downloadedModels.contains(where: { $0.name == model.name }) {
                            HStack(spacing: 8) {
                                Label("Installed", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                Button("Delete") {
                                    try? modelManager.delete(model)
                                }
                                .controlSize(.small)
                            }
                        } else if modelManager.isDownloading {
                            ProgressView(value: modelManager.downloadProgress)
                                .frame(width: 100)
                        } else {
                            Button("Download") {
                                Task { try? await modelManager.download(model) }
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)

                    if model.id != modelManager.availableModels.last?.id {
                        Divider()
                    }
                }
            }

            if !TranscriptionService.isAppleSilicon {
                Divider()
                Label("Intel Mac detected. Transcription runs in batch mode after meetings end.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Divider()

            Text("Summarization Model")
                .fontWeight(.medium)

            Picker("Model", selection: $summarizationModel) {
                ForEach(Self.availableSummarizationModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 280)

            Text("Claude model used to generate meeting summaries.")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(20)
    }
}
