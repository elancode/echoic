import XCTest
@testable import Echoic

/// Serves canned responses per URL path; records request bodies.
private final class StubURLProtocol: URLProtocol {
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
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)
        if let response {
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

final class ModelResolverTests: XCTestCase {
    private var session: URLSession!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)

    private let modelList = """
        {"data": [
          {"id": "claude-sonnet-6", "created_at": "2027-03-01T00:00:00Z"},
          {"id": "claude-opus-5-5", "created_at": "2026-09-01T00:00:00Z"},
          {"id": "claude-opus-6", "created_at": "2027-02-01T00:00:00Z"},
          {"id": "claude-opus-6-fast", "created_at": "2027-02-02T00:00:00Z"},
          {"id": "claude-haiku-5-5", "created_at": "2026-10-01T00:00:00Z"}
        ], "has_more": false}
        """

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
        suiteName = "ModelResolverTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        StubURLProtocol.requests = []
        StubURLProtocol.bodies = []
        StubURLProtocol.handler = nil
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        StubURLProtocol.handler = nil
        session = nil
    }

    private func makeResolver() -> ModelResolver {
        ModelResolver(session: session, defaults: defaults, apiKey: { "test-key" }, now: { [unowned self] in self.now })
    }

    func test_resolve_automaticOpus_picksNewestNonFastOpus() async {
        StubURLProtocol.handler = { [modelList] _ in (200, modelList) }

        let model = await makeResolver().resolve("auto:opus")

        XCTAssertEqual(model, "claude-opus-6")
        XCTAssertEqual(StubURLProtocol.requests.first?.url?.path, "/v1/models")
    }

    func test_resolve_concreteID_passesThroughWithoutNetwork() async {
        let model = await makeResolver().resolve("claude-opus-5-5")

        XCTAssertEqual(model, "claude-opus-5-5")
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func test_resolve_withinCacheLifetime_usesCache() async {
        StubURLProtocol.handler = { [modelList] _ in (200, modelList) }
        let resolver = makeResolver()
        _ = await resolver.resolve("auto:opus")

        now += 60 * 60
        let model = await resolver.resolve("auto:opus")

        XCTAssertEqual(model, "claude-opus-6")
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func test_resolve_lookupFailsWithNoCache_returnsBuiltInDefault() async {
        StubURLProtocol.handler = { _ in (500, "{}") }

        let model = await makeResolver().resolve("auto:opus")

        XCTAssertEqual(model, "claude-opus-5-5")
    }

    func test_resolve_lookupFailsAfterExpiry_returnsStaleCache() async {
        StubURLProtocol.handler = { [modelList] _ in (200, modelList) }
        let resolver = makeResolver()
        _ = await resolver.resolve("auto:opus")

        now += 2 * 24 * 60 * 60
        StubURLProtocol.handler = { _ in (500, "{}") }
        let model = await resolver.resolve("auto:opus")

        XCTAssertEqual(model, "claude-opus-6")
    }

    func test_family_parsesSettingsAndIDs() {
        XCTAssertEqual(ModelResolver.family(of: "auto:opus"), "opus")
        XCTAssertEqual(ModelResolver.family(of: "claude-sonnet-5-5"), "sonnet")
        XCTAssertNil(ModelResolver.family(of: "claude-fable-5-2"))
        XCTAssertEqual(ModelResolver.displayName(for: "auto:opus"), "Latest Opus (automatic)")
        XCTAssertEqual(ModelResolver.displayName(for: "claude-opus-5-5"), "claude-opus-5-5")
    }

    func test_summarize_retiredModel404_retriesWithNewestInFamily() async throws {
        let summaryText = #"{\"title\":\"T\",\"executive_summary\":\"S\",\"decisions\":[],\"action_items\":[]}"#
        StubURLProtocol.handler = { [modelList] request in
            if request.url?.path == "/v1/models" { return (200, modelList) }
            let body = StubURLProtocol.bodies.last ?? ""
            if body.contains("claude-opus-4-6") {
                return (404, #"{"type":"error","error":{"type":"not_found_error"}}"#)
            }
            return (200, #"{"content":[{"type":"text","text":"\#(summaryText)"}],"stop_reason":"end_turn"}"#)
        }
        defaults.set("claude-opus-4-6", forKey: AnthropicClient.summarizationModelKey)
        let client = AnthropicClient(session: session, defaults: defaults, apiKey: { "test-key" })

        let response = try await client.summarize(transcript: "hi", systemPrompt: "sys")

        XCTAssertEqual(response.title, "T")
        XCTAssertTrue(StubURLProtocol.bodies.last?.contains("claude-opus-6") == true)
    }
}
