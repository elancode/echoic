import Foundation
import os.log

private let logger = Logger(subsystem: "com.echoic.app", category: "AnthropicClient")

/// Client for the Anthropic API. Sends transcripts for summarization.
/// Critical Rule #1: Only transcript text is sent. Audio stays local always.
/// Critical Rule #3: API key from Keychain only.
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
    private let apiBaseURL = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"
    private static let fallbackBeta = "server-side-fallback-2026-07-01"
    /// Models that accept `fallbacks: "default"`, which reroutes a request the model
    /// declines (`stop_reason: "refusal"`) instead of failing it.
    private static let fallbackModels: Set<String> = [
        "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5", "claude-fable-5-1", "claude-fable-5-2",
    ]

    static func supportsServerSideFallback(model: String) -> Bool {
        fallbackModels.contains(model)
    }
    private let session: URLSession
    private let resolver: ModelResolver
    private let apiKey: () throws -> String

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        apiKey: @escaping () throws -> String = KeychainService.retrieveAPIKey
    ) {
        self.session = session
        self.apiKey = apiKey
        self.resolver = ModelResolver(session: session, defaults: defaults, apiKey: apiKey)
        self.model = defaults.string(forKey: Self.summarizationModelKey) ?? Self.defaultSummarizationModel
        self.liveInsightsModel = defaults.string(forKey: Self.liveInsightsModelKey) ?? Self.defaultLiveInsightsModel
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
        let model = await resolver.resolve(modelSetting)
        do {
            return try await sendMessage(systemPrompt: systemPrompt, userMessage: userMessage, model: model, maxTokens: maxTokens)
        } catch AnthropicError.httpError(let statusCode, let body) where statusCode == 404 {
            guard let family = ModelResolver.family(of: model) else {
                throw AnthropicError.httpError(statusCode: statusCode, body: body)
            }
            let replacement = await resolver.resolve(ModelResolver.automatic(family), forceRefresh: true)
            guard replacement != model else {
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
        let apiKey = try apiKey()

        let request = try buildRequest(
            apiKey: apiKey,
            model: model,
            maxTokens: maxTokens,
            systemPrompt: systemPrompt,
            userMessage: userMessage
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AnthropicError.httpError(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }

        return try Self.extractText(data)
    }

    // MARK: - Request Building

    private func buildRequest(
        apiKey: String,
        model: String,
        maxTokens: Int,
        systemPrompt: String,
        userMessage: String
    ) throws -> URLRequest {
        guard let url = URL(string: apiBaseURL) else {
            throw AnthropicError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Thinking models can take minutes on a long transcript; the 60s default is too short.
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        if Self.supportsServerSideFallback(model: model) {
            request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
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

    /// Validates an API key by making a minimal request.
    func validateAPIKey(_ key: String) async throws -> Bool {
        guard let url = URL(string: apiBaseURL) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            // Only the auth result matters; use a concrete ID without a network lookup.
            "model": ModelResolver.family(of: model).flatMap { ModelResolver.builtInDefaults[$0] } ?? model,
            "max_tokens": 1,
            "messages": [
                ["role": "user", "content": "hi"]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else { return false }

        // 200 = valid, 401 = invalid key, others = valid key but other issue
        return httpResponse.statusCode != 401
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
}

extension AnthropicError {
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Anthropic API URL"
        case .invalidResponse: return "Invalid response from the Anthropic API"
        case .httpError(let statusCode, let body):
            return "Anthropic API returned HTTP \(statusCode): \(body?.prefix(300) ?? "")"
        case .parseError: return "Couldn't parse the Anthropic API response"
        case .rateLimited: return "Rate limited by the Anthropic API"
        case .serverError: return "Anthropic API server error"
        }
    }
}
