import Foundation
@testable import GraphLinkGenerated

enum Fixtures {

    // ── Client factories ──────────────────────────────────────────────────────

    static func newClient(_ adapter: MockAdapter, _ wsAdapter: MockWebSocketAdapter) -> GraphLinkClient {
        GraphLinkClient(adapter: adapter.execute, wsAdapter: wsAdapter, multipartAdapter: MockMultipartAdapter().executeMultipart)
    }

    static func newClientWithUpload(_ adapter: MockAdapter, _ wsAdapter: MockWebSocketAdapter, _ multipart: MockMultipartAdapter) -> GraphLinkClient {
        GraphLinkClient(adapter: adapter.execute, wsAdapter: wsAdapter, multipartAdapter: multipart.executeMultipart)
    }

    // ── Address ───────────────────────────────────────────────────────────────

    static let kAddressJson = n(
        ("street", "123 Main St"),
        ("city", "Springfield"),
        ("country", "US"),
        ("zip", "12345")
    )

    static let kAddressNoZipJson = n(
        ("street", "456 Oak Ave"),
        ("city", "Shelbyville"),
        ("country", "US"),
        ("zip", nil)
    )

    static let kBillingAddressJson = n(
        ("street", "789 Pine Rd"),
        ("city", "Capital City"),
        ("country", "US"),
        ("zip", "99999")
    )

    // ── Users ─────────────────────────────────────────────────────────────────

    /// Alice — ACTIVE, priority HIGH, no billingAddress, has tags and scores.
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

    /// Bob — INACTIVE, priority null, has billingAddress, empty tags, null scores.
    static let kUserBobJson: [String: Any?] = n(
        ("id", "user-2"),
        ("name", "Bob Jones"),
        ("email", "bob@test.com"),
        ("status", "INACTIVE"),
        ("priority", nil),
        ("address", kAddressNoZipJson),
        ("billingAddress", kBillingAddressJson),
        ("tags", [String]()),
        ("scores", nil),
        ("posts", nil)
    )

    // ── AllScalars ────────────────────────────────────────────────────────────

    /// All nullable fields are null.
    static let kAllScalarsNullJson = n(
        ("id", "scalar-1"),
        ("strVal", "hello world"),
        ("intVal", 42),
        ("floatVal", 3.14),
        ("boolVal", true),
        ("nullableStr", nil),
        ("nullableInt", nil),
        ("nullableFloat", nil),
        ("nullableBool", nil),
        ("nullableId", nil)
    )

    /// All nullable fields present; also tests negative numbers and false bool.
    static let kAllScalarsPresentJson = n(
        ("id", "scalar-2"),
        ("strVal", "edge case"),
        ("intVal", -1),
        ("floatVal", -0.5),
        ("boolVal", false),
        ("nullableStr", "present"),
        ("nullableInt", 99),
        ("nullableFloat", 2.718),
        ("nullableBool", false),
        ("nullableId", "nid-1")
    )

    // ── Post ──────────────────────────────────────────────────────────────────

    static let kPostJson: [String: Any?] = n(
        ("id", "post-1"),
        ("title", "Hello World"),
        ("body", "Post body text."),
        ("author", kUserAliceJson),
        ("coAuthor", nil),
        ("viewCount", 128)
    )

    static let kPostWithCoAuthorJson: [String: Any?] = n(
        ("id", "post-2"),
        ("title", "Collaboration"),
        ("body", "Written together."),
        ("author", kUserAliceJson),
        ("coAuthor", kUserBobJson),
        ("viewCount", 42)
    )

    // ── AuditEntry ────────────────────────────────────────────────────────────

    /// internalNote absent — matches @glSkipOnClient output.
    static let kAuditEntryJson = n(
        ("id", "audit-1"),
        ("action", "LOGIN"),
        ("performedBy", "user-1")
    )

    /// Extra server-only field — client should silently ignore it.
    static let kAuditEntryWithExtraJson = n(
        ("id", "audit-2"),
        ("action", "LOGOUT"),
        ("performedBy", "user-1"),
        ("internalNote", "this should be silently ignored")
    )

    // ── Cyclic fixtures (User → Post → User) ──────────────────────────────────

    /// Post whose author is a minimal User with posts: null (cycle broken here).
    static let kPostWithAuthorCycleJson: [String: Any?] = n(
        ("id", "post-10"),
        ("title", "Cyclic Post"),
        ("body", "Body text."),
        ("author", n(
            ("id", "user-1"),
            ("name", "Alice Smith"),
            ("email", "alice@test.com"),
            ("status", "ACTIVE"),
            ("priority", "HIGH"),
            ("address", kAddressJson),
            ("billingAddress", nil),
            ("tags", ["admin"]),
            ("scores", nil),
            ("posts", nil)
        )),
        ("coAuthor", nil),
        ("viewCount", 7)
    )

    /// Alice with one post; post's author has posts: null (cycle broken).
    static let kUserWithPostsJson: [String: Any?] = n(
        ("id", "user-1"),
        ("name", "Alice Smith"),
        ("email", "alice@test.com"),
        ("status", "ACTIVE"),
        ("priority", "HIGH"),
        ("address", kAddressJson),
        ("billingAddress", nil),
        ("tags", ["admin", "beta"]),
        ("scores", [10, 20, 30]),
        ("posts", [kPostWithAuthorCycleJson])
    )

    // ── Tags ──────────────────────────────────────────────────────────────────

    static let kTagsJson: [[String: Any?]] = [
        n(("id", "tag-1"), ("label", "dart"), ("color", "#0175C2")),
        n(("id", "tag-2"), ("label", "graphql"), ("color", nil)),
    ]

    // ── Errors ────────────────────────────────────────────────────────────────

    static let kGraphQLError: [String: Any?] = n(
        ("message", "Not found"),
        ("locations", [n(("line", 1), ("column", 1))]),
        ("path", ["getUser"])
    )
}
