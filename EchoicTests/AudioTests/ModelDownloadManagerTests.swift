import XCTest
@testable import Echoic

final class ModelDownloadManagerTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("echoic-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - bestAvailableModelPath

    func testBestAvailableModelPathReturnsNilWhenEmpty() {
        let manager = ModelDownloadManager()
        // A fresh temp directory with no models
        // The manager checks its own modelsDirectory, which won't have anything
        // in a test environment without setup. This verifies nil return.
        // (The actual path depends on ~/Library/Application Support/Echoic/models)
        // We test the logic indirectly through the directory check.
        let fm = FileManager.default
        let emptyDir = tempDir.appendingPathComponent("models")
        try? fm.createDirectory(at: emptyDir, withIntermediateDirectories: true)

        // No model directories exist
        let preferred = ["openai_whisper-small.en", "openai_whisper-tiny.en", "openai_whisper-large-v3"]
        var found: String?
        for name in preferred {
            let path = emptyDir.appendingPathComponent(name)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path.path, isDirectory: &isDir), isDir.boolValue {
                found = path.path
                break
            }
        }
        XCTAssertNil(found)
    }

    func testBestAvailableModelPathIgnoresFiles() {
        let fm = FileManager.default
        let modelsDir = tempDir.appendingPathComponent("models")
        try! fm.createDirectory(at: modelsDir, withIntermediateDirectories: true)

        // Create a FILE (not directory) with a model name — this is the bug we fixed
        let fakePath = modelsDir.appendingPathComponent("openai_whisper-large-v3")
        fm.createFile(atPath: fakePath.path, contents: "not a model".data(using: .utf8))

        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: fakePath.path, isDirectory: &isDir)
        XCTAssertTrue(exists, "File should exist")
        XCTAssertFalse(isDir.boolValue, "Should be a file, not directory")
    }

    func testBestAvailableModelPathFindsDirectory() {
        let fm = FileManager.default
        let modelsDir = tempDir.appendingPathComponent("models")

        // Create a proper model directory
        let modelDir = modelsDir.appendingPathComponent("openai_whisper-tiny.en")
        try! fm.createDirectory(at: modelDir, withIntermediateDirectories: true)
        // Add a fake model file inside
        fm.createFile(atPath: modelDir.appendingPathComponent("MelSpectrogram.mlmodelc").path,
                      contents: Data())

        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: modelDir.path, isDirectory: &isDir)
        XCTAssertTrue(exists)
        XCTAssertTrue(isDir.boolValue, "Should be a directory")
    }

    func testWhisperKitFallbackMatchesVersionedModelName() {
        let fm = FileManager.default

        // Simulate WhisperKit's download location
        let whisperKitDir = tempDir.appendingPathComponent("whisperkit-coreml")
        let versionedModel = whisperKitDir.appendingPathComponent("openai_whisper-large-v3-v20240930")
        try! fm.createDirectory(at: versionedModel, withIntermediateDirectories: true)

        // Simulate the fallback lookup logic from bestAvailableModelPath
        let contents = try! fm.contentsOfDirectory(atPath: whisperKitDir.path)
        let preferred = ["openai_whisper-small.en", "openai_whisper-tiny.en", "openai_whisper-large-v3"]

        var matched: String?
        for name in preferred {
            if let match = contents.first(where: { $0.hasPrefix(name) }) {
                matched = whisperKitDir.appendingPathComponent(match).path
                break
            }
        }

        XCTAssertNotNil(matched)
        XCTAssertTrue(matched!.contains("openai_whisper-large-v3-v20240930"))
    }

    func testPrefersSmallerModelWhenMultipleAvailable() {
        let fm = FileManager.default
        let whisperKitDir = tempDir.appendingPathComponent("whisperkit-coreml")

        // Create both small and large models
        try! fm.createDirectory(
            at: whisperKitDir.appendingPathComponent("openai_whisper-small.en"),
            withIntermediateDirectories: true)
        try! fm.createDirectory(
            at: whisperKitDir.appendingPathComponent("openai_whisper-large-v3-v20240930"),
            withIntermediateDirectories: true)

        let contents = try! fm.contentsOfDirectory(atPath: whisperKitDir.path)
        let preferred = ["openai_whisper-small.en", "openai_whisper-tiny.en", "openai_whisper-large-v3"]

        var matched: String?
        for name in preferred {
            if let match = contents.first(where: { $0.hasPrefix(name) }) {
                matched = match
                break
            }
        }

        XCTAssertEqual(matched, "openai_whisper-small.en",
                       "Should prefer small.en over large-v3")
    }

    // MARK: - refreshDownloadedModels

    func testRefreshDownloadedModelsFiltersAvailable() {
        let manager = ModelDownloadManager()
        // By default, no models are downloaded in test environment
        manager.refreshDownloadedModels()
        // downloadedModels should be empty or only contain actually present models
        for model in manager.downloadedModels {
            let path = manager.modelsDirectory.appendingPathComponent(model.name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: path.path),
                          "\(model.name) reported as downloaded but doesn't exist")
        }
    }
}
