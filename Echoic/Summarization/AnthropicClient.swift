import Foundation

/// Client for the Anthropic API. Sends transcripts for summarization.
/// Critical Rule #1: Only transcript text is sent. Audio stays local always.
/// Critical Rule #3: API key from Keychain only.
final class AnthropicClient {
    private let model: String
    private let apiBaseURL = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        self.model = UserDefaults.standard.string(forKey: "summarizationModel") ?? "claude-sonnet-4-6"
    }

    /// Sends a transcript for summarization and returns structured JSON.
    func summarize(transcript: String, systemPrompt: String) async throws -> SummaryResponse {
        let apiKey = try KeychainService.retrieveAPIKey()

        let request = try buildRequest(
            apiKey: apiKey,
            systemPrompt: systemPrompt,
            userMessage: transcript
        )

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw AnthropicError.httpError(statusCode: httpResponse.statusCode, body: String(data: data, encoding: .utf8))
        }

        return try parseResponse(data)
    }

    // MARK: - Request Building

    private func buildRequest(apiKey: String, systemPrompt: String, userMessage: String) throws -> URLRequest {
        guard let url = URL(string: apiBaseURL) else {
            throw AnthropicError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Response Parsing

    private func parseResponse(_ data: Data) throws -> SummaryResponse {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let content = json?["content"] as? [[String: Any]],
              let firstBlock = content.first,
              let text = firstBlock["text"] as? String else {
            throw AnthropicError.parseError
        }

        // Strip markdown code fences if present (```json ... ```)
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

        return try JSONDecoder().decode(SummaryResponse.self, from: jsonData)
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
            "model": model,
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

enum AnthropicError: Error {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, body: String?)
    case parseError
    case rateLimited(retryAfter: TimeInterval?)
    case serverError
}
