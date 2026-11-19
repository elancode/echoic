import Foundation
import GRDB
import os.log

private let logger = Logger(subsystem: "com.echoic.app", category: "LiveInsights")

/// Produces live insights from transcript text. Only text is ever sent (Critical Rule #1).
protocol InsightGenerating {
    func generateInsight(systemPrompt: String, userMessage: String) async throws -> LiveInsightResponse
}

extension AnthropicClient: InsightGenerating {}

/// UI-facing state of the live insights agent.
enum LiveInsightsStatus: Equatable {
    /// Turned off in Settings, or live transcription isn't running.
    case disabled
    /// No Anthropic API key in the Keychain.
    case needsAPIKey
    /// Listening; will update when enough new discussion has accumulated.
    case waiting
    case updating
    /// The last update failed; the next cycle will retry.
    case failed
}

/// Watches the live transcript during a recording and periodically asks the model
/// for an updated recap, open concerns, and questions. Each update is persisted.
@MainActor
final class LiveInsightsEngine {
    /// Called whenever a new insight snapshot is available.
    var onUpdate: ((LiveInsight) -> Void)?
    /// Called whenever `status` changes.
    var onStatusChange: ((LiveInsightsStatus) -> Void)?
    /// Optional note from the user about the meeting's purpose, sent with each request.
    var contextNote = ""

    private(set) var current: LiveInsight?
    private(set) var status: LiveInsightsStatus = .waiting {
        didSet {
            if status != oldValue { onStatusChange?(status) }
        }
    }
    /// The request currently running, if any. Internal so tests can await it.
    private(set) var inFlightTask: Task<Void, Never>?

    private let meetingId: String
    private let generator: InsightGenerating
    private let databaseWriter: any DatabaseWriter
    private let policy: LiveInsightPolicy
    private let retryConfig: RetryHandler.Config
    private let now: () -> Date

    /// Already-seen transcript of this length is resent before new lines for continuity.
    private static let overlapMs: Int64 = 120_000
    private static let tickNanoseconds: UInt64 = 2_000_000_000

    private var segments: [TranscriptSegment] = []
    /// Transcript end time the agent has already seen.
    private var coveredUntilMs: Int64 = 0
    private var lastSegmentAt: Date?
    private var lastRunAt: Date?
    private var tickTask: Task<Void, Never>?
    private var isStopped = false

    init(
        meetingId: String,
        generator: InsightGenerating,
        databaseWriter: any DatabaseWriter,
        policy: LiveInsightPolicy = LiveInsightPolicy(),
        retryConfig: RetryHandler.Config = RetryHandler.Config(maxAttempts: 3, initialDelay: 2, maxDelay: 20),
        now: @escaping () -> Date = Date.init
    ) {
        self.meetingId = meetingId
        self.generator = generator
        self.databaseWriter = databaseWriter
        self.policy = policy
        self.retryConfig = retryConfig
        self.now = now
    }

    // MARK: - Lifecycle

    /// Starts the periodic check that catches pauses in the conversation.
    func start() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.tickNanoseconds)
                guard !Task.isCancelled else { return }
                self?.evaluate()
            }
        }
    }

    /// Stops checking and cancels any in-flight request. Results arriving later are dropped.
    func stop() {
        isStopped = true
        tickTask?.cancel()
        tickTask = nil
        inFlightTask?.cancel()
    }

    // MARK: - Inputs

    /// Feed the full, time-ordered live transcript whenever it changes.
    func segmentsDidChange(_ segments: [TranscriptSegment]) {
        self.segments = segments
        lastSegmentAt = now()
        evaluate()
    }

    /// Forces an update now if anything new has been said.
    func refresh() {
        evaluate(manual: true)
    }

    /// Runs the trigger policy and starts a request if it says so.
    func evaluate(manual: Bool = false) {
        guard !isStopped else { return }
        let currentTime = now()
        let newSegments = segments.filter { $0.endMs > coveredUntilMs }
        let newSpeechMs = newSegments.reduce(Int64(0)) { $0 + max(0, $1.endMs - $1.startMs) }

        let shouldRun = policy.shouldRun(
            newSpeechMs: newSpeechMs,
            secondsSinceLastSegment: lastSegmentAt.map { currentTime.timeIntervalSince($0) } ?? 0,
            secondsSinceLastRun: lastRunAt.map { currentTime.timeIntervalSince($0) },
            inFlight: inFlightTask != nil,
            manual: manual
        )
        guard shouldRun else { return }
        run(newSegments: newSegments, at: currentTime)
    }

    // MARK: - Private

    private func run(newSegments: [TranscriptSegment], at time: Date) {
        let overlapStart = (newSegments.first?.startMs ?? 0) - Self.overlapMs
        let earlierSegments = segments.filter { $0.endMs <= coveredUntilMs && $0.startMs >= overlapStart }
        let coversUntil = segments.map(\.endMs).max() ?? coveredUntilMs

        let message = LiveInsightPromptTemplate.userMessage(
            previous: current,
            contextNote: contextNote,
            earlierSegments: earlierSegments,
            newSegments: newSegments
        )

        lastRunAt = time
        status = .updating
        let generator = generator
        let retryConfig = retryConfig

        inFlightTask = Task { [weak self] in
            do {
                let response = try await RetryHandler.withRetry(config: retryConfig) {
                    try await generator.generateInsight(
                        systemPrompt: LiveInsightPromptTemplate.systemPrompt,
                        userMessage: message
                    )
                }
                await self?.apply(response, coversUntil: coversUntil)
            } catch {
                self?.fail(error)
            }
            self?.inFlightTask = nil
        }
    }

    private func apply(_ response: LiveInsightResponse, coversUntil: Int64) async {
        guard !isStopped, !Task.isCancelled else { return }
        coveredUntilMs = max(coveredUntilMs, coversUntil)

        if response.hasUpdate, let recap = response.recap, !recap.isEmpty {
            var insight = LiveInsight(
                meetingId: meetingId,
                createdAt: Int64(now().timeIntervalSince1970 * 1000),
                coversUntilMs: coveredUntilMs,
                recap: recap,
                concerns: Array((response.concerns ?? []).prefix(3)),
                questions: Array((response.questions ?? []).prefix(3))
            )
            do {
                insight = try await databaseWriter.write { [insight] db in
                    var stored = insight
                    try stored.insert(db)
                    return stored
                }
            } catch {
                // Still show it — persistence is best-effort during a recording.
                logger.error("Failed to store live insight: \(error.localizedDescription)")
            }
            guard !isStopped else { return }
            current = insight
            onUpdate?(insight)
        }
        status = .waiting
    }

    private func fail(_ error: Error) {
        guard !isStopped, !Task.isCancelled else { return }
        logger.error("Live insight update failed: \(error.localizedDescription, privacy: .public)")
        status = .failed
    }
}
