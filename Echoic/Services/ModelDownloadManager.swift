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

    /// Shared instance so background downloads show progress in Settings.
    static let shared = ModelDownloadManager()

    /// Large v3 Turbo: 4-layer decoder (vs 32), several times faster with
    /// near-identical accuracy. Much lighter on the Neural Engine during calls.
    static let recommendedModel = ModelInfo(
        name: "openai_whisper-large-v3-v20240930_turbo",
        displayName: "Large v3 Turbo (Recommended) — ~1.6 GB",
        sizeBytes: 1_640_000_000,
        variant: "large-v3-v20240930_turbo"
    )

    /// Standard models available for download, in order of preference.
    static let defaultModels: [ModelInfo] = [
        recommendedModel,
        ModelInfo(
            name: "openai_whisper-large-v3",
            displayName: "Large v3 — ~2.9 GB (slower, heavier during calls)",
            sizeBytes: 2_900_000_000,
            variant: "large-v3"
        ),
    ]

    private let baseDirectoryOverride: URL?

    /// - Parameter baseDirectory: Override for tests; defaults to Application Support/Echoic.
    init(baseDirectory: URL? = nil) {
        self.baseDirectoryOverride = baseDirectory
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
        if let baseDirectoryOverride { return baseDirectoryOverride }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
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

        // Download into a staging folder and move into place only when complete,
        // so an interrupted download never looks like an installed model.
        let stagingBase = baseDirectory.appendingPathComponent(".staging", isDirectory: true)
        try? FileManager.default.removeItem(at: stagingBase)
        defer { try? FileManager.default.removeItem(at: stagingBase) }

        let stagedFolder = try await WhisperKit.download(
            variant: model.variant,
            downloadBase: stagingBase
        ) { [weak self] progress in
            Task { @MainActor in
                self?.downloadProgress = progress.fractionCompleted
            }
        }

        try Self.installDownloadedModel(at: stagedFolder, as: model.name, into: modelsDirectory)
        logger.info("Installed model \(model.name)")

        await MainActor.run {
            downloadProgress = 1.0
            refreshDownloadedModels()
        }
    }

    /// Moves a fully downloaded model folder into the models directory,
    /// replacing any previous copy.
    static func installDownloadedModel(at source: URL, as name: String, into modelsDirectory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        let destination = modelsDirectory.appendingPathComponent(name, isDirectory: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: source, to: destination)
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
        downloadedModels = availableModels.filter(isInstalled)
    }

    /// Whether the model's folder exists on disk.
    func isInstalled(_ model: ModelInfo) -> Bool {
        findModelFolder(named: model.name) != nil
    }

    // MARK: - Prewarm

    private static let prewarmMarker = ".echoic-prewarmed"

    /// Whether the model has been loaded once (Neural Engine compile done).
    func isPrewarmed(_ model: ModelInfo) -> Bool {
        guard let folder = findModelFolder(named: model.name) else { return false }
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent(Self.prewarmMarker).path)
    }

    func markPrewarmed(_ model: ModelInfo) {
        guard let folder = findModelFolder(named: model.name) else { return }
        Self.markPrewarmed(modelFolder: folder)
    }

    /// Records that a model folder loaded successfully.
    static func markPrewarmed(modelFolder: URL) {
        let marker = modelFolder.appendingPathComponent(prewarmMarker)
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        FileManager.default.createFile(atPath: marker.path, contents: Data())
    }

    /// Downloads the recommended model if missing, then loads it once so the
    /// one-time Neural Engine compile happens now rather than during a call.
    /// Each step is skipped while another app is using the mic (likely a call);
    /// it's retried on next launch.
    func prepareRecommendedModelIfNeeded() async {
        let model = Self.recommendedModel
        guard !isDownloading, !isPrewarmed(model) else { return }
        guard await !Self.isMicInUse() else {
            logger.info("Deferring \(model.name) setup: microphone in use")
            return
        }

        if !isInstalled(model) {
            logger.info("Downloading recommended model \(model.name)")
            do {
                try await download(model)
            } catch {
                logger.error("Recommended model download failed: \(error.localizedDescription)")
                return
            }
            guard await !Self.isMicInUse() else {
                logger.info("Deferring \(model.name) prewarm: microphone in use")
                return
            }
        }

        guard let folder = findModelFolder(named: model.name) else { return }
        logger.info("Prewarming \(model.name)")
        let service = TranscriptionService()
        do {
            try await service.initialize(modelFolder: folder.path) // marks prewarmed on success
            await service.unloadModel()
        } catch {
            logger.error("Prewarm failed for \(model.name): \(error.localizedDescription)")
        }
    }

    private static func isMicInUse() async -> Bool {
        await Task.detached(priority: .utility) {
            MicrophoneActivityMonitor.currentUsage().isInUse
        }.value
    }

    /// Returns the path to the best available model.
    func bestAvailableModelPath() -> String? {
        // The recommended model is only used once it has been prewarmed: its first
        // load compiles it for the Neural Engine (~3 min of heavy CPU), which must
        // not happen during a call. Until then, fall back to an older model.
        for model in Self.defaultModels {
            guard let match = findModelFolder(named: model.name) else { continue }
            if model.name == Self.recommendedModel.name, !isPrewarmed(model) { continue }
            return match.path
        }
        // Nothing else installed: use the recommended model even if not prewarmed
        return findModelFolder(named: Self.recommendedModel.name)?.path
    }

    /// Tokenizer files WhisperKit needs alongside the CoreML models.
    static let tokenizerFiles = ["tokenizer.json", "tokenizer_config.json"]

    /// Tokenizer files not yet present in the model folder.
    static func missingTokenizerFiles(in modelFolder: URL) -> [String] {
        tokenizerFiles.filter {
            !FileManager.default.fileExists(atPath: modelFolder.appendingPathComponent($0).path)
        }
    }

    /// Ensures `tokenizer.json` and `tokenizer_config.json` exist in the model folder.
    ///
    /// The argmaxinc CoreML repos don't ship tokenizer files. Without them, WhisperKit's
    /// tokenizer loader falls through to a HuggingFace Hub download path that fails with
    /// "Invalid metadata" errors due to a swift-transformers bug. This downloads the
    /// files directly from the matching OpenAI repo if missing.
    func ensureTokenizerFiles(in modelFolder: URL) async {
        let missing = Self.missingTokenizerFiles(in: modelFolder)
        guard !missing.isEmpty else { return }

        let folderName = modelFolder.lastPathComponent
        guard let repoId = Self.huggingFaceRepoId(from: folderName) else {
            logger.warning("Cannot determine HuggingFace repo for folder: \(folderName)")
            return
        }

        for file in missing {
            guard let downloadURL = URL(string: "https://huggingface.co/\(repoId)/resolve/main/\(file)") else {
                logger.warning("Invalid \(file) URL for repo: \(repoId)")
                continue
            }
            logger.info("Downloading \(file) from \(repoId)")
            do {
                let (data, response) = try await URLSession.shared.data(from: downloadURL)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    logger.warning("Failed to download \(file): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    continue
                }
                try data.write(to: modelFolder.appendingPathComponent(file))
                logger.info("Saved \(file) (\(data.count) bytes)")
            } catch {
                logger.warning("Failed to download \(file): \(error.localizedDescription)")
            }
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

        // Strip WhisperKit size/turbo suffixes (e.g. "_turbo", "_632MB"); large-v3
        // variants all share the large-v3 tokenizer.
        if let range = modelName.range(of: #"(_turbo)?(_\d+MB)?$"#, options: .regularExpression) {
            modelName = String(modelName[..<range.lowerBound])
        }

        // Strip WhisperKit version suffix (e.g. "-v20240930")
        if let range = modelName.range(of: #"-v\d{8,}"#, options: .regularExpression) {
            modelName = String(modelName[..<range.lowerBound])
        }

        return "\(org)/\(modelName)"
    }

    /// Finds a model folder by name prefix (WhisperKit may append version suffixes).
    private func findModelFolder(named name: String) -> URL? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: modelsDirectory.path) else {
            return nil
        }
        // Exact match: "openai_whisper-large-v3" must not match the turbo folder
        if let match = contents.first(where: { $0 == name }) {
            let url = modelsDirectory.appendingPathComponent(match)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                return url
            }
        }
        return nil
    }
}
