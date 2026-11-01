import XCTest
@testable import GraphLinkGenerated

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var seen: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.seen.append(request)
        let (status, body) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class UrlSessionGetAdapterTest: XCTestCase {
    private var adapter: DefaultGraphLinkURLSessionGetAdapter!

    override func setUp() {
        super.setUp()
        StubURLProtocol.seen = []
        StubURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        adapter = DefaultGraphLinkURLSessionGetAdapter(
            url: URL(string: "http://localhost/graphql")!,
            headersProvider: { ["Authorization": "Bearer token"] },
            session: URLSession(configuration: configuration)
        )
    }

    private func payload(variables: [String: Any?] = ["id": "user-1"]) throws -> Data {
        try GraphLinkJson.encode([
            "operationName": "persistedLongQuery",
            "variables": variables,
            "extensions": GraphLinkPersistedQueries.extensions("abc"),
        ])
    }

    private func queryItems(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func testIssuesAGetWithTheOperationVariablesAndHashInTheUrl() async throws {
        _ = try await adapter.execute(try payload())

        let request = try XCTUnwrap(StubURLProtocol.seen.first)
        XCTAssertEqual(request.httpMethod, "GET")
        let items = queryItems(request)
        XCTAssertEqual(Set(items.keys), ["operationName", "variables", "extensions"])
        XCTAssertEqual(items["operationName"], "persistedLongQuery")
        XCTAssertEqual(try GraphLinkJson.decode(Data(items["variables"]!.utf8))["id"] as? String, "user-1")
        let persisted = try GraphLinkJson.decode(Data(items["extensions"]!.utf8))["persistedQuery"] as? [String: Any]
        XCTAssertEqual(persisted?["version"] as? Int, 1)
    }

    func testAppliesTheHeadersProvider() async throws {
        _ = try await adapter.execute(try payload())

        XCTAssertEqual(StubURLProtocol.seen.first?.value(forHTTPHeaderField: "Authorization"), "Bearer token")
    }

    func testEscapesAPlusInAVariableSoTheServerDoesNotReadItAsASpace() async throws {
        _ = try await adapter.execute(try payload(variables: ["email": "a+b@test.com"]))

        let raw = try XCTUnwrap(StubURLProtocol.seen.first?.url?.absoluteString)
        XCTAssertFalse(raw.contains("+"))
        XCTAssertEqual(
            try GraphLinkJson.decode(Data(queryItems(StubURLProtocol.seen[0])["variables"]!.utf8))["email"] as? String,
            "a+b@test.com"
        )
    }

    func testMapsA405ToGraphLinkGetNotSupported() async throws {
        StubURLProtocol.handler = { _ in (405, Data()) }

        do {
            _ = try await adapter.execute(try payload())
            XCTFail("expected GraphLinkGetNotSupported")
        } catch is GraphLinkGetNotSupported {}
    }

    func testReturnsTheBodyOfASuccessfulResponse() async throws {
        StubURLProtocol.handler = { _ in (200, Data(#"{"data":{}}"#.utf8)) }

        let data = try await adapter.execute(try payload())

        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"data":{}}"#)
    }
}
