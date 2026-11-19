import Foundation
import os.log

private let logger = Logger(subsystem: "com.echoic.app", category: "ModelResolver")

/// Turns a model setting into a concrete Anthropic model ID.
///
/// The API has no "latest" alias, and models are retired over time, so a hard-coded
/// ID eventually stops working. A setting of `auto:<family>` (e.g. `auto:opus`) resolves
/// to the newest model in that family via the Models API, cached for a day. Concrete IDs
/// pass through unchanged.
final class ModelResolver {
    static let automaticPrefix = "auto:"
    /// Used when the Models API can't be reached and nothing is cached yet.
    static let builtInDefaults = [
        "opus": "claude-opus-5-5",
        "sonnet": "claude-sonnet-5-5",
        "haiku": "claude-haiku-5-5",
    ]

    private let session: URLSession
    private let defaults: UserDefaults
    private let apiKey: () throws -> String
    private let now: () -> Date
    private let cacheLifetime: TimeInterval = 24 * 60 * 60
    private let modelsURL = "https://api.anthropic.com/v1/models?limit=1000"

    init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        apiKey: @escaping () throws -> String = KeychainService.retrieveAPIKey,
        now: @escaping () -> Date = Date.init
    ) {
        self.session = session
        self.defaults = defaults
        self.apiKey = apiKey
        self.now = now
    }

    /// The setting value meaning "always the newest model in this family".
    static func automatic(_ family: String) -> String {
        automaticPrefix + family
    }

    /// Picker label: "Latest Opus (automatic)" for automatic settings, the ID otherwise.
    static func displayName(for setting: String) -> String {
        guard setting.hasPrefix(automaticPrefix), let family = family(of: setting) else { return setting }
        return "Latest \(family.capitalized) (automatic)"
    }

    /// The family ("opus", "sonnet", "haiku") of a setting or a concrete ID like `claude-opus-5-5`.
    static func family(of model: String) -> String? {
        if model.hasPrefix(automaticPrefix) {
            return String(model.dropFirst(automaticPrefix.count))
        }
        let parts = model.split(separator: "-")
        guard parts.count >= 2, parts[0] == "claude" else { return nil }
        let family = String(parts[1])
        return builtInDefaults[family] == nil ? nil : family
    }

    /// Resolves a setting to a concrete model ID. Never throws: falls back to the cached
    /// value, then to the built-in default for the family.
    func resolve(_ setting: String, forceRefresh: Bool = false) async -> String {
        guard setting.hasPrefix(Self.automaticPrefix), let family = Self.family(of: setting) else {
            return setting
        }

        let cached = defaults.string(forKey: cacheKey(family))
        let cachedAt = defaults.object(forKey: cacheDateKey(family)) as? Date
        if !forceRefresh, let cached, let cachedAt, now().timeIntervalSince(cachedAt) < cacheLifetime {
            return cached
        }

        do {
            if let newest = try await newestModel(in: family) {
                defaults.set(newest, forKey: cacheKey(family))
                defaults.set(now(), forKey: cacheDateKey(family))
                return newest
            }
        } catch {
            logger.error("Model lookup failed: \(error.localizedDescription, privacy: .public)")
        }
        return cached ?? Self.builtInDefaults[family] ?? setting
    }

    // MARK: - Private

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

    private func newestModel(in family: String) async throws -> String? {
        guard let url = URL(string: modelsURL) else { throw AnthropicError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(try apiKey(), forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AnthropicError.invalidResponse }
        guard http.statusCode == 200 else {
            throw AnthropicError.httpError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8))
        }

        let prefix = "claude-\(family)-"
        return try JSONDecoder().decode(ModelList.self, from: data).data
            .filter { $0.id.hasPrefix(prefix) && !$0.id.hasSuffix("-fast") }
            // RFC 3339 timestamps sort chronologically as strings
            .max { ($0.createdAt ?? "") < ($1.createdAt ?? "") }?
            .id
    }

    private func cacheKey(_ family: String) -> String { "resolvedModel.\(family)" }
    private func cacheDateKey(_ family: String) -> String { "resolvedModel.\(family).date" }
}
