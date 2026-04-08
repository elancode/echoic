import SwiftUI

/// First-run onboarding flow:
/// Screen Recording permission → Mic permission → API key → Model download.
struct OnboardingView: View {
    @State private var currentStep: OnboardingStep = .welcome
    @State private var apiKey = ""
    @State private var apiKeyValid = false
    @State private var isValidating = false
    @StateObject private var modelManager = ModelDownloadManager()
    @Environment(\.dismiss) private var dismiss

    enum OnboardingStep: Int, CaseIterable {
        case welcome
        case screenRecording
        case microphone
        case apiKey
        case modelDownload
        case complete
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 4) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step.rawValue <= currentStep.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 20)

            Spacer()

            // Step content
            Group {
                switch currentStep {
                case .welcome:
                    WelcomeStep()
                case .screenRecording:
                    ScreenRecordingStep()
                case .microphone:
                    MicrophoneStep()
                case .apiKey:
                    APIKeyStep(apiKey: $apiKey, isValid: $apiKeyValid, isValidating: $isValidating)
                case .modelDownload:
                    ModelDownloadStep(modelManager: modelManager)
                case .complete:
                    CompleteStep()
                }
            }
            .padding(30)

            Spacer()

            // Navigation
            HStack {
                if currentStep != .welcome {
                    Button("Back") {
                        withAnimation {
                            currentStep = OnboardingStep(rawValue: currentStep.rawValue - 1) ?? .welcome
                        }
                    }
                }

                Spacer()

                if currentStep == .complete {
                    Button("Get Started") {
                        UserDefaults.standard.set(true, forKey: "onboardingComplete")
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Continue") {
                        withAnimation {
                            currentStep = OnboardingStep(rawValue: currentStep.rawValue + 1) ?? .complete
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(currentStep == .apiKey && !apiKeyValid && !apiKey.isEmpty)
                }
            }
            .padding(30)
        }
        .frame(width: 500, height: 420)
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            Text("Welcome to Echoic")
                .font(.title)
                .fontWeight(.semibold)

            Text("Echoic captures meeting audio, transcribes it locally, identifies speakers, and generates structured summaries. All audio stays on your Mac.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }
}

private struct ScreenRecordingStep: View {
    @State private var hasPermission = AudioCaptureService.hasScreenCapturePermission()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.inset.filled.and.person.filled")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("Screen Recording Permission")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Echoic needs Screen Recording permission to capture system audio from your meetings. No video or screen content is ever captured — only audio.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if hasPermission {
                Label("Permission granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Grant Permission") {
                    _ = AudioCaptureService.requestScreenCapturePermission()
                    // Re-check after a moment
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        hasPermission = AudioCaptureService.hasScreenCapturePermission()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct MicrophoneStep: View {
    @State private var granted = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Microphone (Optional)")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Enable microphone access to identify you as a speaker in transcripts. Your voice is labeled \"You\" in the transcript. Mic audio is never uploaded — it stays on your Mac.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            if granted {
                Label("Permission granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Button("Enable Microphone") {
                    Task {
                        granted = await MicrophoneCaptureService.requestPermission()
                    }
                }
                .buttonStyle(.bordered)

                Text("You can skip this step and enable it later in Settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct APIKeyStep: View {
    @Binding var apiKey: String
    @Binding var isValid: Bool
    @Binding var isValidating: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Anthropic API Key")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Enter your Anthropic API key for meeting summarization. Your key is stored securely in the macOS Keychain — never on disk.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            SecureField("sk-ant-...", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 350)

            Button(isValidating ? "Validating..." : "Validate & Save") {
                validateAndSave()
            }
            .disabled(apiKey.isEmpty || isValidating)

            if isValid {
                Label("Key validated and saved", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }

            Text("You can skip this step. Summaries won't be available without an API key, but transcription and diarization work locally.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func validateAndSave() {
        isValidating = true
        Task {
            let client = AnthropicClient()
            let valid = (try? await client.validateAPIKey(apiKey)) ?? false

            await MainActor.run {
                isValidating = false
                if valid {
                    try? KeychainService.saveAPIKey(apiKey)
                    isValid = true
                }
            }
        }
    }
}

private struct ModelDownloadStep: View {
    @ObservedObject var modelManager: ModelDownloadManager

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.purple)

            Text("Download Transcription Model")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose a WhisperKit model. The small model is recommended for most users.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                ForEach(modelManager.availableModels) { model in
                    HStack {
                        Text(model.displayName)
                            .font(.subheadline)
                        Spacer()

                        if modelManager.downloadedModels.contains(where: { $0.name == model.name }) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else if modelManager.isDownloading {
                            ProgressView(value: modelManager.downloadProgress)
                                .frame(width: 80)
                        } else {
                            Button("Download") {
                                Task { try? await modelManager.download(model) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

private struct CompleteStep: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("You're All Set!")
                .font(.title)
                .fontWeight(.semibold)

            Text("Click the waveform icon in your menu bar to start recording your first meeting.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
    }
}
