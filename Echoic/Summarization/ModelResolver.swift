import Foundation
import os.log

private let logger = Logger(subsystem: "com.echoic.app", category: "ModelResolver")

/// Turns a model setting into a concrete model ID for the current provider.
///
/// There is no "latest" alias, and models are retired over time, so a hard-coded ID
/// eventually stops working. A setting of `auto:<family>` (e.g. `auto:opus`) resolves to
/// the newest model in that family the provider offers, cached for a day per provider.
/// Concrete IDs pass through unchanged.
final class ModelResolver {
    static let automaticPrefix = "auto:"
    /// Used on the Claude API when the Models API can't be reached and nothing is cached yet.
    static let builtInDefaults = AnthropicAPIProvider.builtInDefaults

    private let provider: ClaudeProvider
    private let defaults: UserDefaults
    private let now: () -> Date
    private let cacheLifetime: TimeInterval = 24 * 60 * 60

    init(provider: ClaudeProvider, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.provider = provider
        self.defaults = defaults
        self.now = now
    }

    /// Claude API resolver (kept for callers and tests that pass a session and key).
    convenience init(
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        apiKey: @escaping () throws -> String = KeychainService.retrieveAPIKey,
        now: @escaping () -> Date = Date.init
    ) {
        self.init(provider: AnthropicAPIProvider(session: session, apiKey: apiKey), defaults: defaults, now: now)
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

    /// The family ("opus", "sonnet", "haiku") of a setting, a Claude API ID like
    /// `claude-opus-5-5`, or a Bedrock ID like `us.anthropic.claude-opus-5-5-v1:0`.
    static func family(of model: String) -> String? {
        if model.hasPrefix(automaticPrefix) {
            return String(model.dropFirst(automaticPrefix.count))
        }
        let name = model.split(separator: ".").first { $0.hasPrefix("claude-") }.map(String.init) ?? model
        let parts = name.split(separator: "-")
        guard parts.count >= 2, parts[0] == "claude" else { return nil }
        let family = String(parts[1])
        return builtInDefaults[family] == nil ? nil : family
    }

    /// Resolves a setting to a concrete model ID: the newest model, else the cached
    /// value, else the provider's built-in default. Nil only when none of those exist
    /// (e.g. Bedrock before its first successful lookup).
    func resolve(_ setting: String, forceRefresh: Bool = false) async -> String? {
        // A Claude API ID picked in Settings (e.g. `claude-opus-5-5`) means "this family"
        // on providers with their own IDs.
        if !provider.acceptsClaudeAPIModelIDs, setting.hasPrefix("claude-"), let family = Self.family(of: setting) {
            return await resolve(Self.automatic(family), forceRefresh: forceRefresh)
        }
        guard setting.hasPrefix(Self.automaticPrefix), let family = Self.family(of: setting) else {
            return setting
        }

        let cached = defaults.string(forKey: cacheKey(family))
        let cachedAt = defaults.object(forKey: cacheDateKey(family)) as? Date
        if !forceRefresh, let cached, let cachedAt, now().timeIntervalSince(cachedAt) < cacheLifetime {
            return cached
        }

        do {
            if let newest = try await provider.newestModel(in: family) {
                defaults.set(newest, forKey: cacheKey(family))
                defaults.set(now(), forKey: cacheDateKey(family))
                return newest
            }
        } catch {
            logger.error("Model lookup failed: \(error.localizedDescription, privacy: .public)")
        }
        return cached ?? provider.builtInModel(for: family)
    }

    // Claude API entries keep their original keys so existing caches stay valid.
    private var namespace: String {
        provider.cacheNamespace == "anthropic" ? "" : "\(provider.cacheNamespace)."
    }

    private func cacheKey(_ family: String) -> String { "resolvedModel.\(namespace)\(family)" }
    private func cacheDateKey(_ family: String) -> String { "resolvedModel.\(namespace)\(family).date" }
}
