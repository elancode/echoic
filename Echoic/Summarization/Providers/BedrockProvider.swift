import AWSBedrock
import AWSBedrockRuntime
import AWSSDKIdentity
import ClientRuntime
import Foundation

/// A Claude model offered to this account in this region (a system-defined
/// inference profile such as `us.anthropic.claude-opus-5-5-v1:0`).
struct BedrockModel: Equatable {
    let id: String
    let createdAt: Date?
}

/// Pure request and model-choice logic shared by both Bedrock auth modes.
///
/// Bedrock takes the same Messages body as the Claude API through InvokeModel, with
/// three changes: the model goes in the URL, the version goes in the body as
/// `anthropic_version`, and beta flags go in the body as `anthropic_beta`.
enum BedrockRequest {
    static let anthropicVersion = "bedrock-2023-05-31"

    static func invokeBody(from body: [String: Any], betas: [String]) throws -> Data {
        var body = body
        body.removeValue(forKey: "model")
        body.removeValue(forKey: "fallbacks") // Claude API only
        body["anthropic_version"] = anthropicVersion
        if !betas.isEmpty { body["anthropic_beta"] = betas }
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func invokeURL(region: String, modelId: String) throws -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard isValidRegion(region),
              let encoded = modelId.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://bedrock-runtime.\(region).amazonaws.com/model/\(encoded)/invoke") else {
            throw AnthropicError.invalidURL
        }
        return url
    }

    static func inferenceProfilesURL(region: String) throws -> URL {
        guard isValidRegion(region),
              let url = URL(string: "https://bedrock.\(region).amazonaws.com/inference-profiles?type=SYSTEM_DEFINED&maxResults=1000") else {
            throw AnthropicError.invalidURL
        }
        return url
    }

    /// Region names are lowercase letters, digits and hyphens (e.g. `us-east-1`).
    static func isValidRegion(_ region: String) -> Bool {
        !region.isEmpty && region.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" } && region.allSatisfy(\.isASCII)
    }

    /// The newest Claude model in a family. Prefers a regional profile (`us.`, `eu.`, …),
    /// which keeps requests in that geography, over a `global.` one.
    static func newestModel(in family: String, from models: [BedrockModel]) -> String? {
        let matching = models.filter { $0.id.contains("anthropic.claude-\(family)-") }
        let regional = matching.filter { !$0.id.hasPrefix("global.") }
        return (regional.isEmpty ? matching : regional)
            .max { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }?
            .id
    }
}

// MARK: - API key

/// Bedrock with a Bedrock API key (`Authorization: Bearer`). Short-term keys last at
/// most 12 hours and work in one region only.
struct BedrockAPIKeyProvider: ClaudeProvider {
    let region: String
    var session: URLSession = .shared
    var apiKey: () throws -> String = KeychainService.retrieveBedrockAPIKey

    var cacheNamespace: String { "bedrock.\(region)" }
    var supportsServerSideFallback: Bool { false }
    var acceptsClaudeAPIModelIDs: Bool { false }

    func send(body: [String: Any], model: String, betas: [String]) async throws -> Data {
        var request = URLRequest(url: try BedrockRequest.invokeURL(region: region, modelId: model))
        request.httpMethod = "POST"
        // Bedrock allows up to 60 minutes for Claude inference.
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(try apiKey())", forHTTPHeaderField: "Authorization")
        request.httpBody = try BedrockRequest.invokeBody(from: body, betas: betas)
        return try await HTTPCheck.data(for: request, session: session)
    }

    func listModels() async throws -> [BedrockModel] {
        var request = URLRequest(url: try BedrockRequest.inferenceProfilesURL(region: region))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(try apiKey())", forHTTPHeaderField: "Authorization")
        let data = try await HTTPCheck.data(for: request, session: session)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProfileList.self, from: data).inferenceProfileSummaries
            .filter { $0.status == nil || $0.status == "ACTIVE" }
            .map { BedrockModel(id: $0.inferenceProfileId, createdAt: $0.createdAt) }
    }

    func newestModel(in family: String) async throws -> String? {
        BedrockRequest.newestModel(in: family, from: try await listModels())
    }

    func builtInModel(for family: String) -> String? { nil }

    private struct ProfileList: Decodable {
        struct Summary: Decodable {
            let inferenceProfileId: String
            let status: String?
            let createdAt: Date?
        }
        let inferenceProfileSummaries: [Summary]
    }
}

// MARK: - AWS profile

/// Bedrock with SigV4-signed requests, using credentials from a named profile in
/// ~/.aws/config: SSO, `credential_process` (e.g. corporate credential helpers), or
/// static keys. Echoic never stores these credentials.
struct BedrockProfileProvider: ClaudeProvider {
    let region: String
    let profile: String

    var cacheNamespace: String { "bedrock.\(region)" }
    var supportsServerSideFallback: Bool { false }
    var acceptsClaudeAPIModelIDs: Bool { false }

    private var credentials: ProfileAWSCredentialIdentityResolver {
        ProfileAWSCredentialIdentityResolver(profileName: profile)
    }

    func send(body: [String: Any], model: String, betas: [String]) async throws -> Data {
        let config = try await BedrockRuntimeClient.BedrockRuntimeClientConfig(
            awsCredentialIdentityResolver: credentials, region: region
        )
        let client = BedrockRuntimeClient(config: config)
        let input = InvokeModelInput(
            accept: "application/json",
            body: try BedrockRequest.invokeBody(from: body, betas: betas),
            contentType: "application/json",
            modelId: model
        )
        do {
            guard let data = try await client.invokeModel(input: input).body else {
                throw AnthropicError.invalidResponse
            }
            return data
        } catch {
            throw Self.mapped(error)
        }
    }

    func listModels() async throws -> [BedrockModel] {
        let config = try await BedrockClient.BedrockClientConfig(awsCredentialIdentityResolver: credentials, region: region)
        let client = BedrockClient(config: config)
        do {
            let output = try await client.listInferenceProfiles(
                input: ListInferenceProfilesInput(maxResults: 1000, typeEquals: .systemDefined)
            )
            return (output.inferenceProfileSummaries ?? [])
                .filter { $0.status == nil || $0.status == .active }
                .compactMap { summary in summary.inferenceProfileId.map { BedrockModel(id: $0, createdAt: summary.createdAt) } }
        } catch {
            throw Self.mapped(error)
        }
    }

    func newestModel(in family: String) async throws -> String? {
        BedrockRequest.newestModel(in: family, from: try await listModels())
    }

    func builtInModel(for family: String) -> String? { nil }

    /// Maps AWS service errors to `AnthropicError.httpError`, so retries and messages
    /// work the same as for the Claude API.
    private static func mapped(_ error: Error) -> Error {
        guard let httpError = error as? HTTPError else { return error }
        let message = (error as? ServiceError)?.message
        return AnthropicError.httpError(statusCode: httpError.httpResponse.statusCode.rawValue, body: message)
    }
}
