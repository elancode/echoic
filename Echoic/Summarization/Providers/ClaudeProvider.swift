import Foundation

/// Where Claude requests go. Prompts, request bodies and response parsing are
/// shared (`AnthropicClient`); a provider only owns the endpoint, auth, and model IDs.
/// Critical Rule #1: only transcript text is sent, whichever provider is used.
protocol ClaudeProvider {
    /// Distinguishes cached model resolutions between providers and regions.
    var cacheNamespace: String { get }
    /// Whether the endpoint accepts `fallbacks: "default"` (the Claude API does; Bedrock doesn't).
    var supportsServerSideFallback: Bool { get }
    /// Whether IDs like `claude-opus-5-5` work as-is. Bedrock uses inference profile IDs.
    var acceptsClaudeAPIModelIDs: Bool { get }

    /// Sends a Messages API body (including `model`) and returns the raw response.
    /// Throws `AnthropicError.httpError` for non-200 responses.
    func send(body: [String: Any], model: String, betas: [String]) async throws -> Data

    /// The newest available model ID in a family ("opus", "sonnet", "haiku"), or nil.
    func newestModel(in family: String) async throws -> String?

    /// A known-good ID to use when the model lookup fails and nothing is cached.
    /// Nil where IDs depend on the account (Bedrock inference profiles).
    func builtInModel(for family: String) -> String?
}

enum ClaudeProviderKind: String, CaseIterable {
    case anthropic
    case bedrock

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic API"
        case .bedrock: return "Amazon Bedrock"
        }
    }
}

enum BedrockAuthMode: String, CaseIterable {
    /// AWS credentials from a named profile in ~/.aws/config (SSO, credential_process,
    /// static keys). Nothing is stored by Echoic.
    case awsProfile
    /// A Bedrock API key (bearer token), stored in the Keychain.
    case apiKey

    var displayName: String {
        switch self {
        case .awsProfile: return "AWS profile"
        case .apiKey: return "Bedrock API key"
        }
    }
}

/// The provider choice. Non-secret, so it lives in UserDefaults; keys stay in the Keychain.
struct ClaudeProviderSettings: Equatable {
    static let kindKey = "claudeProvider"
    static let bedrockRegionKey = "bedrockRegion"
    static let bedrockAuthKey = "bedrockAuthMode"
    static let bedrockProfileKey = "bedrockProfile"
    static let defaultRegion = "us-east-1"
    static let defaultProfile = "default"

    var kind: ClaudeProviderKind
    var bedrockRegion: String
    var bedrockAuth: BedrockAuthMode
    var bedrockProfile: String

    init(defaults: UserDefaults = .standard) {
        kind = defaults.string(forKey: Self.kindKey).flatMap(ClaudeProviderKind.init(rawValue:)) ?? .anthropic
        bedrockRegion = defaults.string(forKey: Self.bedrockRegionKey).flatMap(Self.nonEmpty) ?? Self.defaultRegion
        bedrockAuth = defaults.string(forKey: Self.bedrockAuthKey).flatMap(BedrockAuthMode.init(rawValue:)) ?? .awsProfile
        bedrockProfile = defaults.string(forKey: Self.bedrockProfileKey).flatMap(Self.nonEmpty) ?? Self.defaultProfile
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum ClaudeProviders {
    /// The provider selected in Settings.
    static func current(defaults: UserDefaults = .standard, session: URLSession = .shared) -> ClaudeProvider {
        let settings = ClaudeProviderSettings(defaults: defaults)
        switch settings.kind {
        case .anthropic:
            return AnthropicAPIProvider(session: session)
        case .bedrock:
            switch settings.bedrockAuth {
            case .apiKey:
                return BedrockAPIKeyProvider(region: settings.bedrockRegion, session: session)
            case .awsProfile:
                return BedrockProfileProvider(region: settings.bedrockRegion, profile: settings.bedrockProfile)
            }
        }
    }

    /// Whether the selected provider has what it needs to make a request.
    static func isConfigured(defaults: UserDefaults = .standard) -> Bool {
        let settings = ClaudeProviderSettings(defaults: defaults)
        switch (settings.kind, settings.bedrockAuth) {
        case (.anthropic, _):
            return (try? KeychainService.retrieveAPIKey()) != nil
        case (.bedrock, .apiKey):
            return (try? KeychainService.retrieveBedrockAPIKey()) != nil
        case (.bedrock, .awsProfile):
            return true // resolved per request from ~/.aws/config
        }
    }
}

// MARK: - Anthropic API

/// The Claude API at api.anthropic.com, authenticated with an API key.
struct AnthropicAPIProvider: ClaudeProvider {
    static let messagesURL = "https://api.anthropic.com/v1/messages"
    static let modelsURL = "https://api.anthropic.com/v1/models?limit=1000"
    static let apiVersion = "2023-06-01"
    /// Used when the Models API can't be reached and nothing is cached yet.
    static let builtInDefaults = [
        "opus": "claude-opus-5-5",
        "sonnet": "claude-sonnet-5-5",
        "haiku": "claude-haiku-5-5",
    ]

    var session: URLSession = .shared
    var apiKey: () throws -> String = KeychainService.retrieveAPIKey

    var cacheNamespace: String { "anthropic" }
    var supportsServerSideFallback: Bool { true }
    var acceptsClaudeAPIModelIDs: Bool { true }

    func send(body: [String: Any], model: String, betas: [String]) async throws -> Data {
        guard let url = URL(string: Self.messagesURL) else { throw AnthropicError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Thinking models can take minutes on a long transcript; the 60s default is too short.
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try apiKey(), forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        if !betas.isEmpty {
            request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta")
        }
        var body = body
        body["model"] = model
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await HTTPCheck.data(for: request, session: session)
    }

    func newestModel(in family: String) async throws -> String? {
        guard let url = URL(string: Self.modelsURL) else { throw AnthropicError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(try apiKey(), forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        let data = try await HTTPCheck.data(for: request, session: session)

        let prefix = "claude-\(family)-"
        return try JSONDecoder().decode(ModelList.self, from: data).data
            .filter { $0.id.hasPrefix(prefix) && !$0.id.hasSuffix("-fast") }
            // RFC 3339 timestamps sort chronologically as strings
            .max { ($0.createdAt ?? "") < ($1.createdAt ?? "") }?
            .id
    }

    func builtInModel(for family: String) -> String? {
        Self.builtInDefaults[family]
    }

    /// Checks a key with a minimal request: 401 means invalid; anything else means the key works.
    func validate(key: String, model: String) async throws -> Bool {
        guard let url = URL(string: Self.messagesURL) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "max_tokens": 1, "messages": [["role": "user", "content": "hi"]],
        ] as [String: Any])
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode != 401
    }

    private struct ModelList: Decodable {
        struct Model: Decodable {
            let id: String
            let createdAt: String?

            enum CodingKeys: String, CodingKey {
                case id
                case createdAt = "created_at"
            }
        }
        let data: [Model]
    }
}

/// Sends a request and maps non-200 responses to `AnthropicError.httpError`.
enum HTTPCheck {
    static func data(for request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AnthropicError.invalidResponse }
        guard http.statusCode == 200 else {
            throw AnthropicError.httpError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return data
    }
}
