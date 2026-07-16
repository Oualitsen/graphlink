import Foundation
@testable import GraphLinkGenerated

enum Fixtures {
    static let SERVER_URL = URL(string: "http://localhost:9999/graphql")!
    static let WS_URL = URL(string: "ws://localhost:9999/graphql")!
    static let UPLOAD_URL = URL(string: "http://localhost:9998/graphql")!

    /// Real client, talking to the main test server (queries/mutations/subscriptions).
    static func newRealClient() -> GraphLinkClient {
        GraphLinkClient.create(url: SERVER_URL, wsUrl: WS_URL)
    }

    /// Real client whose multipart adapter targets the upload server (port 9998).
    static func newUploadClient() -> GraphLinkClient {
        let httpAdapter = DefaultGraphLinkURLSessionAdapter(url: SERVER_URL)
        let wsAdapter = DefaultGraphLinkWebSocketAdapter(url: WS_URL)
        let multipartAdapter = DefaultGraphLinkURLSessionMultipartAdapter(url: UPLOAD_URL)
        return GraphLinkClient(adapter: httpAdapter.execute, wsAdapter: wsAdapter, multipartAdapter: multipartAdapter.executeMultipart)
    }

    /// Mock-adapter client — used only by CacheTest, mirroring the Kotlin real-tier
    /// CacheTest.kt which also relies on MockAdapter for call-count assertions
    /// (there is no way to count real-server round-trips otherwise).
    static func newClient(_ adapter: MockAdapter, _ wsAdapter: MockWebSocketAdapter) -> GraphLinkClient {
        GraphLinkClient(adapter: adapter.execute, wsAdapter: wsAdapter, multipartAdapter: MockMultipartAdapter().executeMultipart)
    }

    // ── Cache-test fixtures (mock JSON, mirrors Kotlin real-tier Fixtures.kt) ──

    static let kAddressJson = n(
        ("street", "123 Main St"),
        ("city", "Springfield"),
        ("country", "US"),
        ("zip", "12345")
    )

    static let kUserAliceJson: [String: Any?] = n(
        ("id", "user-1"),
        ("name", "Alice Smith"),
        ("email", "alice@test.com"),
        ("status", "ACTIVE"),
        ("priority", "HIGH"),
        ("address", kAddressJson),
        ("billingAddress", nil),
        ("tags", ["admin", "beta"]),
        ("scores", [10, 20, 30]),
        ("posts", nil)
    )

    static let kUserBobJson: [String: Any?] = n(
        ("id", "user-2"),
        ("name", "Bob Jones"),
        ("email", "bob@test.com"),
        ("status", "INACTIVE"),
        ("priority", nil),
        ("address", kAddressJson),
        ("billingAddress", nil),
        ("tags", [String]()),
        ("scores", nil),
        ("posts", nil)
    )

    static let kPostJson: [String: Any?] = n(
        ("id", "post-1"),
        ("title", "Hello World"),
        ("body", "Post body text."),
        ("author", kUserAliceJson),
        ("coAuthor", nil),
        ("viewCount", 128)
    )
}
