import Foundation

/// Downloads and manages WhisperKit CoreML model bundles.
final class ModelDownloadManager: ObservableObject {
    @Published var downloadProgress: Double = 0
    @Published var isDownloading = false
    @Published var availableModels: [ModelInfo] = []
    @Published var downloadedModels: [ModelInfo] = []

    struct ModelInfo: Identifiable, Codable {
        var id: String { name }
        let name: String
        let displayName: String
        let sizeBytes: Int64
        let url: String
    }

    /// Standard models available for download.
    static let defaultModels: [ModelInfo] = [
        ModelInfo(
            name: "openai_whisper-large-v3",
            displayName: "Large v3 (Multilingual) — ~600 MB",
            sizeBytes: 600_000_000,
            url: "https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/main/openai_whisper-large-v3"
        )
    ]

    init() {
        availableModels = Self.defaultModels
        refreshDownloadedModels()
    }

    /// Directory where models are stored.
    var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("Echoic", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
    }

    /// Downloads a model.
    func download(_ model: ModelInfo) async throws {
        guard !isDownloading else { return }

        await MainActor.run {
            isDownloading = true
            downloadProgress = 0
        }

        defer {
            Task { @MainActor in
                isDownloading = false
            }
        }

        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let destinationDir = modelsDirectory.appendingPathComponent(model.name, isDirectory: true)

        guard let url = URL(string: model.url) else { return }

        let (tempURL, _) = try await URLSession.shared.download(from: url, delegate: DownloadDelegate { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = progress
            }
        })

        // Move to final location
        if FileManager.default.fileExists(atPath: destinationDir.path) {
            try FileManager.default.removeItem(at: destinationDir)
        }
        try FileManager.default.moveItem(at: tempURL, to: destinationDir)

        await MainActor.run {
            downloadProgress = 1.0
            refreshDownloadedModels()
        }
    }

    /// Deletes a downloaded model.
    func delete(_ model: ModelInfo) throws {
        let path = modelsDirectory.appendingPathComponent(model.name)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
        refreshDownloadedModels()
    }

    /// Checks which models are downloaded (app directory + WhisperKit default location).
    func refreshDownloadedModels() {
        let fm = FileManager.default
        let whisperKitDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml")
        let whisperKitContents = (try? fm.contentsOfDirectory(atPath: whisperKitDir.path)) ?? []

        downloadedModels = availableModels.filter { model in
            // Check app's own models directory
            let appPath = modelsDirectory.appendingPathComponent(model.name)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: appPath.path, isDirectory: &isDir), isDir.boolValue {
                return true
            }
            // Check WhisperKit's default download location (with version suffixes)
            return whisperKitContents.contains { $0.hasPrefix(model.name) }
        }
    }

    /// Returns the path to the best available model (prefers small.en).
    /// Checks both the app's models directory and WhisperKit's default download location.
    func bestAvailableModelPath() -> String? {
        let preferred = ["openai_whisper-large-v3"]
        let fm = FileManager.default

        // Check app's own models directory (must be a directory, not a stale file)
        for name in preferred {
            let path = modelsDirectory.appendingPathComponent(name)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path.path, isDirectory: &isDir), isDir.boolValue {
                return path.path
            }
        }

        // Check WhisperKit's default download location (~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/)
        let whisperKitDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/huggingface/models/argmaxinc/whisperkit-coreml")
        if fm.fileExists(atPath: whisperKitDir.path),
           let contents = try? fm.contentsOfDirectory(atPath: whisperKitDir.path) {
            // Match preferred models, allowing version suffixes (e.g. openai_whisper-large-v3-v20240930)
            for name in preferred {
                if let match = contents.first(where: { $0.hasPrefix(name) }) {
                    let path = whisperKitDir.appendingPathComponent(match)
                    return path.path
                }
            }
        }

        return nil
    }
}

// MARK: - Download Delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progressHandler: (Double) -> Void

    init(progressHandler: @escaping (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progressHandler(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
}
