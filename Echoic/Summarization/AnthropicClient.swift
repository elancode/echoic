import Foundation
import os.log

private let logger = Logger(subsystem: "com.echoic.app", category: "AnthropicClient")

/// Claude client for summaries and live insights. Builds Messages requests and parses
/// responses; the provider (Claude API or Amazon Bedrock) handles endpoint and auth.
/// Critical Rule #1: Only transcript text is sent. Audio stays local always.
/// Critical Rule #3: Keys come from the Keychain only.
final class AnthropicClient {
    /// UserDefaults key and default for the model used by live insights during a meeting.
    static let liveInsightsModelKey = "liveInsightsModel"
    /// "Latest Opus": resolved at runtime so the app keeps working when models are retired.
    static let defaultLiveInsightsModel = ModelResolver.automatic("opus")
    /// UserDefaults key and default for the model used for post-meeting summaries.
    static let summarizationModelKey = "summarizationModel"
    static let defaultSummarizationModel = ModelResolver.automatic("opus")

    private let model: String
    private let liveInsightsModel: String
    private static let fallbackBeta = "server-side-fallback-2026-07-01"
    /// Models that accept `fallbacks: "default"`, which reroutes a request the model
    /// declines (`stop_reason: "refusal"`) instead of failing it. Claude API only.
    private static let fallbackModels: Set<String> = [
        "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5", "claude-fable-5-1", "claude-fable-5-2",
    ]

    static func supportsServerSideFallback(model: String) -> Bool {
        fallbackModels.contains(model)
    }

    private let provider: ClaudeProvider
    private let resolver: ModelResolver

    init(provider: ClaudeProvider = ClaudeProviders.current(), defaults: UserDefaults = .standard) {
        self.provider = provider
        self.resolver = ModelResolver(provider: provider, defaults: defaults)
        self.model = defaults.string(forKey: Self.summarizationModelKey) ?? Self.defaultSummarizationModel
        self.liveInsightsModel = defaults.string(forKey: Self.liveInsightsModelKey) ?? Self.defaultLiveInsightsModel
    }

    /// Claude API client (kept for callers and tests that pass a session and key).
    convenience init(
        session: URLSession,
        defaults: UserDefaults = .standard,
        apiKey: @escaping () throws -> String = KeychainService.retrieveAPIKey
    ) {
        self.init(provider: AnthropicAPIProvider(session: session, apiKey: apiKey), defaults: defaults)
    }

    /// Sends a transcript for summarization and returns structured JSON.
    func summarize(transcript: String, systemPrompt: String) async throws -> SummaryResponse {
        // Thinking counts toward max_tokens on current models; leave room for the JSON.
        let text = try await send(systemPrompt: systemPrompt, userMessage: transcript, modelSetting: model, maxTokens: 16000)
        return try Self.decodeJSON(SummaryResponse.self, from: text)
    }

    /// Sends the rolling live-insight prompt and returns the updated state.
    func generateInsight(systemPrompt: String, userMessage: String) async throws -> LiveInsightResponse {
        let text = try await send(
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            modelSetting: liveInsightsModel,
            maxTokens: 8192 // thinking counts toward this; leave room for the JSON
        )
        return try Self.decodeJSON(LiveInsightResponse.self, from: text)
    }

    /// Resolves the model setting and sends the message. If the model no longer exists
    /// (HTTP 404, e.g. retired), retries once with the newest model in the same family.
    private func send(systemPrompt: String, userMessage: String, modelSetting: String, maxTokens: Int) async throws -> String {
        guard let model = await resolver.resolve(modelSetting) else { throw AnthropicError.noModelAvailable }
        do {
            return try await sendMessage(systemPrompt: systemPrompt, userMessage: userMessage, model: model, maxTokens: maxTokens)
        } catch AnthropicError.httpError(let statusCode, let body) where statusCode == 404 {
            guard let family = ModelResolver.family(of: model),
                  let replacement = await resolver.resolve(ModelResolver.automatic(family), forceRefresh: true),
                  replacement != model else {
                throw AnthropicError.httpError(statusCode: statusCode, body: body)
            }
            logger.warning("Model \(model, privacy: .public) unavailable; retrying with \(replacement, privacy: .public)")
            return try await sendMessage(
                systemPrompt: systemPrompt,
                userMessage: userMessage,
                model: replacement,
                maxTokens: maxTokens
            )
        }
    }

    /// Sends a single-turn message and returns the response text.
    func sendMessage(systemPrompt: String, userMessage: String, model: String, maxTokens: Int) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]
        var betas: [String] = []
        if provider.supportsServerSideFallback, Self.supportsServerSideFallback(model: model) {
            betas.append(Self.fallbackBeta)
            body["fallbacks"] = "default"
        }
        return try Self.extractText(try await provider.send(body: body, model: model, betas: betas))
    }

    // MARK: - Response Parsing

    /// Returns the response's text, skipping non-text blocks. Models with adaptive
    /// thinking (e.g. Haiku 5.5) put a `thinking` block before the text.
    static func extractText(_ data: Data) throws -> String {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let content = json?["content"] as? [[String: Any]] else {
            throw AnthropicError.parseError
        }
        let texts = content.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }
        guard !texts.isEmpty else {
            throw AnthropicError.parseError
        }
        return texts.joined()
    }

    /// Decodes model output as JSON, stripping markdown code fences if present.
    static func decodeJSON<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        var jsonText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonText.hasPrefix("```") {
            // Remove opening fence (```json or ```)
            if let firstNewline = jsonText.firstIndex(of: "\n") {
                jsonText = String(jsonText[jsonText.index(after: firstNewline)...])
            }
            // Remove closing fence
            if jsonText.hasSuffix("```") {
                jsonText = String(jsonText.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard let jsonData = jsonText.data(using: .utf8) else {
            throw AnthropicError.parseError
        }

        return try JSONDecoder().decode(T.self, from: jsonData)
    }

    /// Validates a Claude API key by making a minimal request.
    func validateAPIKey(_ key: String) async throws -> Bool {
        // Only the auth result matters; use a concrete ID without a network lookup.
        let concrete = ModelResolver.family(of: model).flatMap { ModelResolver.builtInDefaults[$0] } ?? model
        return try await AnthropicAPIProvider().validate(key: key, model: concrete)
    }
}

// MARK: - Response Types

struct SummaryResponse: Codable {
    let title: String
    let meetingType: String?
    let participants: String?
    let durationTone: String?
    let executiveSummary: String
    let detailedSummary: String?
    let decisions: [Decision]
    let actionItems: [ActionItem]
    let notableQuotes: [NotableQuote]?
    /// Questions raised but not resolved. Absent in summaries made before this field existed.
    let openQuestions: [String]?
    /// Topics in the order discussed, each with where it starts.
    let topics: [Topic]?
    /// Names inferred for diarized speakers, keyed by speaker label (e.g. "speaker_1").
    let speakerNames: [String: String]?

    enum CodingKeys: String, CodingKey {
        case title
        case meetingType = "meeting_type"
        case participants
        case durationTone = "duration_tone"
        case executiveSummary = "executive_summary"
        case detailedSummary = "detailed_summary"
        case decisions
        case actionItems = "action_items"
        case notableQuotes = "notable_quotes"
        case openQuestions = "open_questions"
        case topics
        case speakerNames = "speaker_names"
    }

    struct Decision: Codable {
        let decision: String
        let speaker: String?
        let timestampMs: Int64?

        enum CodingKeys: String, CodingKey {
            case decision, speaker
            case timestampMs = "timestamp_ms"
        }
    }

    struct ActionItem: Codable {
        let task: String
        let owner: String?
        let due: String?
    }

    struct Topic: Codable {
        let topic: String
        let timestampMs: Int64?

        enum CodingKeys: String, CodingKey {
            case topic
            case timestampMs = "timestamp_ms"
        }
    }

    struct NotableQuote: Codable {
        let quote: String
        let speaker: String?
        let context: String?
    }
}

// MARK: - Errors

enum AnthropicError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case parseError
    case rateLimited(retryAfter: TimeInterval?)
    case serverError
    /// No model could be resolved (e.g. Bedrock with no Claude models available yet).
    case noModelAvailable
}

extension AnthropicError {
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Claude endpoint URL. Check the Bedrock region in Settings."
        case .invalidResponse: return "Invalid response from Claude"
        case .httpError(let statusCode, let body):
            return "Claude request failed (HTTP \(statusCode)): \(body?.prefix(300) ?? "")"
        case .parseError: return "Couldn't parse Claude's response"
        case .rateLimited: return "Rate limited by the Claude provider"
        case .serverError: return "Claude provider server error"
        case .noModelAvailable:
            return "No Claude model is available. On Amazon Bedrock, check the region and that Claude models are enabled for your account."
        }
    }
}
