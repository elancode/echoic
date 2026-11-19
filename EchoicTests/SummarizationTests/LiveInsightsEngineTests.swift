import XCTest
import GRDB
@testable import Echoic

private final class MockInsightGenerator: InsightGenerating {
    var responses: [Result<LiveInsightResponse, Error>] = []
    var delayNanoseconds: UInt64 = 0
    private(set) var userMessages: [String] = []

    func generateInsight(systemPrompt: String, userMessage: String) async throws -> LiveInsightResponse {
        userMessages.append(userMessage)
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        guard !responses.isEmpty else { return LiveInsightResponse(hasUpdate: false) }
        return try responses.removeFirst().get()
    }
}

@MainActor
final class LiveInsightsEngineTests: XCTestCase {
    private let meetingId = "01HTEST0000000000000INSIGHT"
    private var dbQueue: DatabaseQueue!
    private var generator: MockInsightGenerator!
    private var now = Date(timeIntervalSince1970: 1_700_000_000)
    private var engine: LiveInsightsEngine!

    override func setUp() async throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(configuration: config)
        try DatabaseManager.migrate(dbQueue)
        try await dbQueue.write { [meetingId] db in
            try Meeting(id: meetingId, title: "Test", startedAt: 0, status: .recording).insert(db)
        }

        generator = MockInsightGenerator()
        engine = LiveInsightsEngine(
            meetingId: meetingId,
            generator: generator,
            databaseWriter: dbQueue,
            retryConfig: RetryHandler.Config(maxAttempts: 1),
            now: { [unowned self] in self.now }
        )
    }

    override func tearDown() {
        engine.stop()
        engine = nil
        generator = nil
        dbQueue = nil
    }

    /// Segments of 10s each, back to back, covering `seconds` of speech.
    private func segments(seconds: Int64, from start: Int64 = 0) -> [TranscriptSegment] {
        stride(from: start, to: start + seconds, by: 10).map {
            TranscriptSegment(meetingId: meetingId, startMs: $0 * 1000, endMs: ($0 + 10) * 1000,
                              speakerId: nil, text: "line at \($0)", confidence: nil)
        }
    }

    private func update(_ text: String) -> LiveInsightResponse {
        LiveInsightResponse(hasUpdate: true, recap: text, concerns: ["c"], questions: ["q"])
    }

    private func waitForRun() async {
        await engine.inFlightTask?.value
    }

    func test_segmentsDidChange_belowThreshold_doesNotCallGenerator() async {
        engine.segmentsDidChange(segments(seconds: 30))
        await waitForRun()

        XCTAssertTrue(generator.userMessages.isEmpty)
        XCTAssertNil(engine.current)
    }

    func test_segmentsDidChange_thresholdReached_publishesAndPersistsInsight() async throws {
        generator.responses = [.success(update("Discussing launch"))]
        var published: LiveInsight?
        engine.onUpdate = { published = $0 }

        engine.segmentsDidChange(segments(seconds: 90))
        await waitForRun()

        XCTAssertEqual(generator.userMessages.count, 1)
        XCTAssertEqual(engine.current?.recap, "Discussing launch")
        XCTAssertEqual(engine.current?.coversUntilMs, 90_000)
        XCTAssertEqual(published?.recap, "Discussing launch")
        XCTAssertEqual(engine.status, .waiting)

        let stored = try await dbQueue.read { db in try LiveInsight.fetchAll(db) }
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.concerns, ["c"])
    }

    func test_noUpdateResponse_keepsPreviousInsight() async {
        generator.responses = [.success(update("First")), .success(LiveInsightResponse(hasUpdate: false))]

        engine.segmentsDidChange(segments(seconds: 90))
        await waitForRun()
        now += 100
        engine.segmentsDidChange(segments(seconds: 180))
        await waitForRun()

        XCTAssertEqual(generator.userMessages.count, 2)
        XCTAssertEqual(engine.current?.recap, "First")
    }

    func test_secondRun_sendsOnlyNewSegmentsAsNewTranscript() async throws {
        generator.responses = [.success(update("First")), .success(update("Second"))]

        engine.segmentsDidChange(segments(seconds: 90))
        await waitForRun()
        now += 100
        engine.segmentsDidChange(segments(seconds: 180))
        await waitForRun()

        let second = try XCTUnwrap(generator.userMessages.last)
        let newPart = try XCTUnwrap(second.components(separatedBy: "NEW TRANSCRIPT").last)
        XCTAssertFalse(newPart.contains("line at 80"))
        XCTAssertTrue(newPart.contains("line at 90"))
        XCTAssertTrue(second.contains("Recap: First"))
    }

    func test_generatorError_keepsStateAndReportsFailure() async {
        generator.responses = [.failure(AnthropicError.parseError)]

        engine.segmentsDidChange(segments(seconds: 90))
        await waitForRun()

        XCTAssertNil(engine.current)
        XCTAssertEqual(engine.status, .failed)
    }

    func test_refresh_runsImmediatelyWithLittleSpeech() async {
        generator.responses = [.success(update("Manual"))]

        engine.segmentsDidChange(segments(seconds: 10))
        engine.refresh()
        await waitForRun()

        XCTAssertEqual(engine.current?.recap, "Manual")
    }

    func test_pauseAfterEnoughSpeech_triggersRun() async {
        generator.responses = [.success(update("Paused"))]

        engine.segmentsDidChange(segments(seconds: 50))
        await waitForRun()
        XCTAssertTrue(generator.userMessages.isEmpty)

        now += 9
        engine.evaluate()
        await waitForRun()

        XCTAssertEqual(engine.current?.recap, "Paused")
    }

    func test_stop_cancelsInFlightRequest() async {
        generator.responses = [.success(update("Too late"))]
        generator.delayNanoseconds = 5_000_000_000

        engine.segmentsDidChange(segments(seconds: 90))
        let task = engine.inFlightTask
        XCTAssertNotNil(task)
        engine.stop()
        await task?.value

        XCTAssertNil(engine.current)
    }
}
