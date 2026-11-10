import Foundation
import os.log
import WhisperKit

private let logger = Logger(subsystem: "com.echoic.app", category: "ModelDownloadManager")

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

    /// Removes stale HuggingFace download cache that can cause
    /// "Invalid metadata: Could not remove corrupted metadata file" errors.
    func cleanCache() {
        let cacheDir = modelsDirectory.appendingPathComponent(".cache")
        try? FileManager.default.removeItem(at: cacheDir)
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

    /// Ensures `tokenizer_config.json` exists in the model folder.
    ///
    /// WhisperKit's tokenizer loader requires this file alongside `tokenizer.json`.
    /// Without it, the loader falls through to a HuggingFace Hub download path that
    /// fails with "Invalid metadata" errors due to a swift-transformers bug.
    /// This method downloads the file directly from HuggingFace if missing.
    func ensureTokenizerConfig(in modelFolder: URL) async {
        let configURL = modelFolder.appendingPathComponent("tokenizer_config.json")
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }

        // Determine the HuggingFace model name from the folder name
        // e.g. "openai_whisper-large-v3" → "openai/whisper-large-v3"
        let folderName = modelFolder.lastPathComponent
        let repoId = Self.huggingFaceRepoId(from: folderName)
        guard let repoId else {
            logger.warning("Cannot determine HuggingFace repo for folder: \(folderName)")
            return
        }

        guard let downloadURL = URL(string: "https://huggingface.co/\(repoId)/resolve/main/tokenizer_config.json") else {
            logger.warning("Invalid tokenizer_config.json URL for repo: \(repoId)")
            return
        }
        logger.info("Downloading tokenizer_config.json from \(repoId)")

        do {
            let (data, response) = try await URLSession.shared.data(from: downloadURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.warning("Failed to download tokenizer_config.json: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return
            }
            try data.write(to: configURL)
            logger.info("Saved tokenizer_config.json (\(data.count) bytes)")
        } catch {
            logger.warning("Failed to download tokenizer_config.json: \(error.localizedDescription)")
        }
    }

    /// Converts a WhisperKit model folder name to a HuggingFace repo ID.
    /// e.g. "openai_whisper-large-v3" → "openai/whisper-large-v3"
    /// e.g. "openai_whisper-large-v3-v20240930" → "openai/whisper-large-v3"
    static func huggingFaceRepoId(from folderName: String) -> String? {
        // WhisperKit folder names use underscore to separate org from model name
        guard let underscoreIndex = folderName.firstIndex(of: "_") else { return nil }
        let org = String(folderName[..<underscoreIndex])
        var modelName = String(folderName[folderName.index(after: underscoreIndex)...])

        // Strip WhisperKit version suffix (e.g. "-v20240930")
        if let range = modelName.range(of: #"-v\d{8,}"#, options: .regularExpression) {
            modelName = String(modelName[..<range.lowerBound])
        }

        return "\(org)/\(modelName)"
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
