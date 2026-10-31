import XCTest
@testable import GraphLinkGenerated

/// Regression tests for literal `$varName` GraphQL variable syntax in
/// generated query strings.
///
/// Unlike Kotlin, Swift string interpolation uses `\(...)`, not `$name` — so
/// there's no compiler ambiguity to guard against here. These tests are
/// ported for parity anyway: they decode the raw outgoing payload and assert
/// the `query` field contains the literal `$varName` GraphQL variable
/// declarations the generator emitted.
private func lastQuery(_ adapter: MockAdapter) throws -> String {
    let raw = adapter.getLastCall()!.rawPayload
    let decoded = try GraphLinkJson.decode(raw.data(using: .utf8)!)
    return decoded["query"] as! String
}

private let kAddressInput = AddressInput(street: "123 Main St", city: "Springfield", country: "US", zip: "12345")
private let kCreateInput = CreateUserInput(
    name: "Alice Smith",
    email: "alice@test.com",
    status: .active,
    address: kAddressInput
)

// ── Mutations ────────────────────────────────────────────────────────────────

final class QueryStringsTest_MutationQueryStrings: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    func test_createUser_query_containsLiteralDollarInput() async throws {
        adapter.registerData("createUser", n(("createUser", Fixtures.kUserAliceJson)))
        _ = try await client.mutations.createUser(input: kCreateInput)
        let query = try lastQuery(adapter)
        XCTAssertTrue(query.contains("$input"), "Expected '$input' in query but got: \(query)")
    }

    func test_updateUser_query_containsLiteralDollarId_andDollarInput() async throws {
        adapter.registerData("updateUser", n(("updateUser", Fixtures.kUserAliceJson)))
        _ = try await client.mutations.updateUser(id: "user-1", input: UpdateUserInput(name: "Alice"))
        let query = try lastQuery(adapter)
        XCTAssertTrue(query.contains("$id"), "Expected '$id' in query but got: \(query)")
        XCTAssertTrue(query.contains("$input"), "Expected '$input' in query but got: \(query)")
    }

    func test_deleteUser_query_containsLiteralDollarId() async throws {
        adapter.registerData("deleteUser", n(("deleteUser", true)))
        _ = try await client.mutations.deleteUser(id: "user-1")
        let query = try lastQuery(adapter)
        XCTAssertTrue(query.contains("$id"), "Expected '$id' in query but got: \(query)")
    }

    func test_transferPost_query_containsLiteralDollarArgs() async throws {
        adapter.registerData("transferPost", n(("transferPost", Fixtures.kPostJson)))
        _ = try await client.mutations.transferPost(postId: "post-1", newAuthorId: "user-2")
        let query = try lastQuery(adapter)
        XCTAssertTrue(query.contains("$postId"), "Expected '$postId' in query but got: \(query)")
        XCTAssertTrue(query.contains("$newAuthorId"), "Expected '$newAuthorId' in query but got: \(query)")
    }

    func test_query_doesNotContainInputObjectToString() async throws {
        adapter.registerData("createUser", n(("createUser", Fixtures.kUserAliceJson)))
        _ = try await client.mutations.createUser(input: kCreateInput)
        let query = try lastQuery(adapter)
        XCTAssertFalse(query.contains("CreateUserInput("), "Query must not contain a stringified input object; got: \(query)")
    }
}

// ── Simple queries ───────────────────────────────────────────────────────────

final class QueryStringsTest_QueryQueryStrings: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    func test_getUser_query_containsLiteralDollarId() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserAliceJson)))
        _ = try await client.queries.getUser(id: "user-1")
        let query = try lastQuery(adapter)
        XCTAssertTrue(query.contains("$id"), "Expected '$id' in query but got: \(query)")
    }

    func test_listUsersByStatus_query_containsLiteralDollarStatus() async throws {
        adapter.registerData("listUsersByStatus", n(("listUsersByStatus", [Fixtures.kUserAliceJson])))
        _ = try await client.queries.listUsersByStatus(status: .active)
        let query = try lastQuery(adapter)
        XCTAssertTrue(query.contains("$status"), "Expected '$status' in query but got: \(query)")
    }
}

// ── Multi-resolver (combined) query path ────────────────────────────────────

final class QueryStringsTest_PartialQueryStrings: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    func test_fetchUserAndPost_partialQueryStrings_containLiteralDollar() async throws {
        adapter.registerData("fetchUserAndPost", n(
            ("user", Fixtures.kUserAliceJson), ("post", Fixtures.kPostJson)
        ))
        _ = try await client.queries.fetchUserAndPost(userId: "user-1", postId: "post-1")
        let query = try lastQuery(adapter)
        XCTAssertTrue(query.contains("$userId"), "Expected '$userId' in query but got: \(query)")
        XCTAssertTrue(query.contains("$postId"), "Expected '$postId' in query but got: \(query)")
    }

    func test_fetchUserAndPost_query_doesNotContainObjectToString() async throws {
        adapter.registerData("fetchUserAndPost", n(
            ("user", Fixtures.kUserAliceJson), ("post", Fixtures.kPostJson)
        ))
        _ = try await client.queries.fetchUserAndPost(userId: "user-1", postId: "post-1")
        let query = try lastQuery(adapter)
        let containsInterpolatedValues = query.contains("user-1") && query.contains("post-1") && !query.contains("$userId")
        XCTAssertFalse(containsInterpolatedValues, "Query must not contain interpolated arg values; got: \(query)")
    }
}
