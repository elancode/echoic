import XCTest
@testable import Echoic

/// Serves canned responses; records requests and bodies.
private final class BedrockStubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, String))?
    static var requests: [URLRequest] = []
    static var bodies: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        Self.bodies.append(Self.readBody(request))
        guard let handler = Self.handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, body) = handler(request)
        if let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(_ request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

final class BedrockProviderTests: XCTestCase {
    private var session: URLSession!
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let profiles = """
        {"inferenceProfileSummaries": [
          {"inferenceProfileId": "global.anthropic.claude-opus-6-v1:0", "status": "ACTIVE", "createdAt": "2027-02-01T00:00:00Z"},
          {"inferenceProfileId": "us.anthropic.claude-opus-6-v1:0", "status": "ACTIVE", "createdAt": "2027-02-01T00:00:00Z"},
          {"inferenceProfileId": "us.anthropic.claude-opus-5-5-v1:0", "status": "ACTIVE", "createdAt": "2026-09-01T00:00:00Z"},
          {"inferenceProfileId": "us.anthropic.claude-sonnet-6-v1:0", "status": "ACTIVE", "createdAt": "2027-03-01T00:00:00Z"},
          {"inferenceProfileId": "us.meta.llama4-v1:0", "status": "ACTIVE", "createdAt": "2027-04-01T00:00:00Z"}
        ]}
        """

    private let summaryReply = """
        {"content": [{"type": "text", "text": "{\\"title\\": \\"T\\", \\"executive_summary\\": \\"S\\", \\"decisions\\": [], \\"action_items\\": []}"}]}
        """

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BedrockStubURLProtocol.self]
        session = URLSession(configuration: config)
        suiteName = "BedrockProviderTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        BedrockStubURLProtocol.requests = []
        BedrockStubURLProtocol.bodies = []
        BedrockStubURLProtocol.handler = nil
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        BedrockStubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeProvider(region: String = "us-west-2") -> BedrockAPIKeyProvider {
        BedrockAPIKeyProvider(region: region, session: session, apiKey: { "bedrock-key" })
    }

    // MARK: - Request translation

    func test_invokeBody_messagesBody_movesModelAndVersionForBedrock() throws {
        let body: [String: Any] = [
            "model": "claude-opus-5-5", "max_tokens": 10, "fallbacks": "default",
            "messages": [["role": "user", "content": "hi"]],
        ]

        let data = try BedrockRequest.invokeBody(from: body, betas: ["some-beta-2026-01-01"])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(json["model"])
        XCTAssertNil(json["fallbacks"], "Bedrock has no server-side fallbacks")
        XCTAssertEqual(json["anthropic_version"] as? String, "bedrock-2023-05-31")
        XCTAssertEqual(json["anthropic_beta"] as? [String], ["some-beta-2026-01-01"])
        XCTAssertEqual(json["max_tokens"] as? Int, 10)
    }

    func test_invokeBody_noBetas_omitsBetaField() throws {
        let data = try BedrockRequest.invokeBody(from: ["max_tokens": 1], betas: [])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(json["anthropic_beta"])
    }

    func test_invokeURL_profileIdWithColon_isPercentEncoded() throws {
        let url = try BedrockRequest.invokeURL(region: "us-west-2", modelId: "us.anthropic.claude-opus-5-5-v1:0")

        XCTAssertEqual(
            url.absoluteString,
            "https://bedrock-runtime.us-west-2.amazonaws.com/model/us.anthropic.claude-opus-5-5-v1%3A0/invoke"
        )
    }

    func test_invokeURL_invalidRegion_throws() {
        XCTAssertThrowsError(try BedrockRequest.invokeURL(region: "us west/2", modelId: "m"))
    }

    // MARK: - Model choice

    func test_newestModel_opus_prefersRegionalOverGlobalAndNewestFirst() {
        let candidates = [
            BedrockModel(id: "global.anthropic.claude-opus-6-v1:0", createdAt: Date(timeIntervalSince1970: 200)),
            BedrockModel(id: "us.anthropic.claude-opus-6-v1:0", createdAt: Date(timeIntervalSince1970: 200)),
            BedrockModel(id: "us.anthropic.claude-opus-5-5-v1:0", createdAt: Date(timeIntervalSince1970: 100)),
            BedrockModel(id: "us.anthropic.claude-sonnet-6-v1:0", createdAt: Date(timeIntervalSince1970: 300)),
        ]

        XCTAssertEqual(BedrockRequest.newestModel(in: "opus", from: candidates), "us.anthropic.claude-opus-6-v1:0")
    }

    func test_newestModel_onlyGlobalAvailable_usesGlobal() {
        let candidates = [BedrockModel(id: "global.anthropic.claude-opus-6-v1:0", createdAt: nil)]

        XCTAssertEqual(BedrockRequest.newestModel(in: "opus", from: candidates), "global.anthropic.claude-opus-6-v1:0")
    }

    func test_newestModel_noMatchingFamily_returnsNil() {
        let candidates = [BedrockModel(id: "us.meta.llama4-v1:0", createdAt: nil)]

        XCTAssertNil(BedrockRequest.newestModel(in: "opus", from: candidates))
    }

    func test_family_bedrockIds_parsesFamily() {
        XCTAssertEqual(ModelResolver.family(of: "us.anthropic.claude-opus-5-5-v1:0"), "opus")
        XCTAssertEqual(ModelResolver.family(of: "anthropic.claude-sonnet-5-5"), "sonnet")
        XCTAssertNil(ModelResolver.family(of: "us.meta.llama4-v1:0"))
    }

    func test_resolve_claudeAPIIdOnBedrock_resolvesItsFamily() async {
        BedrockStubURLProtocol.handler = { [profiles] _ in (200, profiles) }
        let resolver = ModelResolver(provider: makeProvider(), defaults: defaults)

        let model = await resolver.resolve("claude-opus-5-5")

        XCTAssertEqual(model, "us.anthropic.claude-opus-6-v1:0")
    }

    func test_resolve_bedrockIdOnBedrock_passesThrough() async {
        let resolver = ModelResolver(provider: makeProvider(), defaults: defaults)

        let model = await resolver.resolve("us.anthropic.claude-opus-5-5-v1:0")

        XCTAssertEqual(model, "us.anthropic.claude-opus-5-5-v1:0")
        XCTAssertTrue(BedrockStubURLProtocol.requests.isEmpty)
    }

    // MARK: - API key provider

    func test_apiKeySend_success_postsBearerToInvokeURL() async throws {
        BedrockStubURLProtocol.handler = { _ in (200, #"{"content": [{"type": "text", "text": "ok"}]}"#) }

        let data = try await makeProvider().send(body: ["max_tokens": 1], model: "us.anthropic.claude-opus-6-v1:0", betas: [])

        let request = try XCTUnwrap(BedrockStubURLProtocol.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer bedrock-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-api-key"))
        XCTAssertEqual(request.url?.path, "/model/us.anthropic.claude-opus-6-v1:0/invoke")
        XCTAssertEqual(try AnthropicClient.extractText(data), "ok")
    }

    func test_apiKeySend_accessDenied_throwsHTTPError() async {
        BedrockStubURLProtocol.handler = { _ in (403, #"{"message": "not authorized"}"#) }

        do {
            _ = try await makeProvider().send(body: [:], model: "m", betas: [])
            XCTFail("Expected an error")
        } catch AnthropicError.httpError(let status, _) {
            XCTAssertEqual(status, 403)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func test_apiKeyListModels_parsesSystemDefinedProfiles() async throws {
        BedrockStubURLProtocol.handler = { [profiles] _ in (200, profiles) }

        let models = try await makeProvider().listModels()

        let url = try XCTUnwrap(BedrockStubURLProtocol.requests.first?.url)
        XCTAssertEqual(url.host, "bedrock.us-west-2.amazonaws.com")
        XCTAssertEqual(url.path, "/inference-profiles")
        XCTAssertTrue(url.query?.contains("type=SYSTEM_DEFINED") ?? false)
        XCTAssertEqual(models.count, 5)
        XCTAssertEqual(models.first?.id, "global.anthropic.claude-opus-6-v1:0")
    }

    // MARK: - Through AnthropicClient

    func test_summarize_onBedrock_resolvesProfileAndSendsWithoutFallbacks() async throws {
        BedrockStubURLProtocol.handler = { [profiles, summaryReply] request in
            request.url?.path == "/inference-profiles" ? (200, profiles) : (200, summaryReply)
        }
        let client = AnthropicClient(provider: makeProvider(), defaults: defaults)

        let summary = try await client.summarize(transcript: "t", systemPrompt: "s")

        XCTAssertEqual(summary.title, "T")
        let invoke = try XCTUnwrap(BedrockStubURLProtocol.requests.last)
        XCTAssertEqual(invoke.url?.path, "/model/us.anthropic.claude-opus-6-v1:0/invoke")
        let body = try XCTUnwrap(BedrockStubURLProtocol.bodies.last)
        XCTAssertFalse(body.contains("fallbacks"))
        XCTAssertFalse(body.contains("\"model\""))
    }

    func test_summarize_onBedrockModelLookupFailsWithNoCache_throwsNoModel() async {
        BedrockStubURLProtocol.handler = { _ in (403, "{}") }
        let client = AnthropicClient(provider: makeProvider(), defaults: defaults)

        do {
            _ = try await client.summarize(transcript: "t", systemPrompt: "s")
            XCTFail("Expected an error")
        } catch AnthropicError.noModelAvailable {
            XCTAssertEqual(BedrockStubURLProtocol.requests.count, 1, "No invoke without a resolved model")
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    // MARK: - Settings

    func test_providerSettings_unset_defaultsToAnthropicAPI() {
        let settings = ClaudeProviderSettings(defaults: defaults)

        XCTAssertEqual(settings.kind, .anthropic)
        XCTAssertEqual(settings.bedrockAuth, .awsProfile)
        XCTAssertEqual(settings.bedrockRegion, "us-east-1")
    }
}
