import Foundation
import WhisperKit

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
        /// WhisperKit model variant string (e.g. "large-v3").
        let variant: String
    }

    /// Standard models available for download.
    static let defaultModels: [ModelInfo] = [
        ModelInfo(
            name: "openai_whisper-large-v3",
            displayName: "Large v3 (Multilingual) — ~1.3 GB",
            sizeBytes: 1_300_000_000,
            variant: "large-v3"
        )
    ]

    init() {
        availableModels = Self.defaultModels
        refreshDownloadedModels()
    }

    /// Echoic's base application support directory.
    /// WhisperKit creates `models/argmaxinc/whisperkit-coreml/<variant>/` under this.
    var baseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Echoic", isDirectory: true)
    }

    /// Directory where WhisperKit stores downloaded models.
    var modelsDirectory: URL {
        baseDirectory
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("argmaxinc", isDirectory: true)
            .appendingPathComponent("whisperkit-coreml", isDirectory: true)
    }

    /// Downloads a model using WhisperKit's built-in HuggingFace download.
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

        _ = try await WhisperKit.download(
            variant: model.variant,
            downloadBase: baseDirectory
        ) { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = progress.fractionCompleted
            }
        }

        await MainActor.run {
            downloadProgress = 1.0
            refreshDownloadedModels()
        }
    }

    /// Deletes a downloaded model.
    func delete(_ model: ModelInfo) throws {
        if let match = findModelFolder(named: model.name) {
            try FileManager.default.removeItem(at: match)
        }
        refreshDownloadedModels()
    }

    /// Checks which models are downloaded.
    func refreshDownloadedModels() {
        downloadedModels = availableModels.filter { model in
            findModelFolder(named: model.name) != nil
        }
    }

    /// Returns the path to the best available model.
    func bestAvailableModelPath() -> String? {
        let preferred = ["openai_whisper-large-v3"]

        for name in preferred {
            if let match = findModelFolder(named: name) {
                return match.path
            }
        }

        return nil
    }

    /// Finds a model folder by name prefix (WhisperKit may append version suffixes).
    private func findModelFolder(named prefix: String) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: modelsDirectory.path) else {
            return nil
        }
        if let match = contents.first(where: { $0.hasPrefix(prefix) }) {
            let url = modelsDirectory.appendingPathComponent(match)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }
        return nil
    }
}
