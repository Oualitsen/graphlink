import XCTest
@testable import GraphLinkGenerated

// Even in the real-server tier, caching call-counts can only be verified via a
// MockAdapter (there is no way to observe real-server round-trips otherwise) —
// mirrors the Kotlin CacheTest.kt in kotlin_client_tests_real, which does the same.

private let kAddressInput = AddressInput(street: "123 Main St", city: "Springfield", country: "US", zip: "12345")
private let kCreateInput = CreateUserInput(
    name: "Alice Smith",
    email: "alice@test.com",
    status: .active,
    address: kAddressInput
)

// ── Cache hit ────────────────────────────────────────────────────────────────

final class CacheTest_CacheHit: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerData("getCachedUser", n(("getCachedUser", Fixtures.kUserAliceJson)))
    }

    func test_firstCall_hitsAdapter() async throws {
        _ = try await client.queries.getCachedUser(id: "user-1")
        XCTAssertEqual(adapter.getCallCount(), 1)
    }

    func test_secondCallSameArg_servedFromCache_noExtraAdapterCall() async throws {
        _ = try await client.queries.getCachedUser(id: "user-1")
        _ = try await client.queries.getCachedUser(id: "user-1")
        XCTAssertEqual(adapter.getCallCount(), 1)
    }

    func test_cachedResponse_hasCorrectData() async throws {
        _ = try await client.queries.getCachedUser(id: "user-1")
        let res = try await client.queries.getCachedUser(id: "user-1")
        XCTAssertNotNil(res.getCachedUser)
        XCTAssertEqual(res.getCachedUser.id, "user-1")
    }

    func test_differentArg_bypassesCache() async throws {
        adapter.registerData("getCachedUser", n(("getCachedUser", Fixtures.kUserBobJson)))
        _ = try await client.queries.getCachedUser(id: "user-1")
        _ = try await client.queries.getCachedUser(id: "user-2")
        XCTAssertEqual(adapter.getCallCount(), 2)
    }
}

// ── Tag-based invalidation ───────────────────────────────────────────────────

final class CacheTest_TagInvalidation: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    func test_createCachedUser_invalidatesUsersTag_nextGetCachedUserRefetches() async throws {
        adapter.registerData("getCachedUser", n(("getCachedUser", Fixtures.kUserAliceJson)))
        adapter.registerData("createCachedUser", n(("createCachedUser", Fixtures.kUserAliceJson)))

        _ = try await client.queries.getCachedUser(id: "user-1")
        XCTAssertEqual(adapter.getCallCount(), 1)

        _ = try await client.mutations.createCachedUser(input: kCreateInput)
        XCTAssertEqual(adapter.getCallCount(), 2)

        _ = try await client.queries.getCachedUser(id: "user-1")
        XCTAssertEqual(adapter.getCallCount(), 3)
    }

    func test_resetAll_invalidatesAllTags_allCachedQueriesRefetch() async throws {
        adapter.registerData("getCachedUser", n(("getCachedUser", Fixtures.kUserAliceJson)))
        adapter.registerData("getCachedPost", n(("getCachedPost", Fixtures.kPostJson)))
        adapter.registerData("resetAll", n(("resetAll", true)))

        _ = try await client.queries.getCachedUser(id: "user-1")
        _ = try await client.queries.getCachedPost(id: "post-1")
        XCTAssertEqual(adapter.getCallCount(), 2)

        _ = try await client.mutations.resetAll()
        XCTAssertEqual(adapter.getCallCount(), 3)

        _ = try await client.queries.getCachedUser(id: "user-1")
        _ = try await client.queries.getCachedPost(id: "post-1")
        XCTAssertEqual(adapter.getCallCount(), 5)
    }
}

// ── Cross-tag isolation ──────────────────────────────────────────────────────

final class CacheTest_CrossTagIsolation: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    func test_usersTagInvalidation_doesNotAffect_postsCache() async throws {
        adapter.registerData("getCachedPost", n(("getCachedPost", Fixtures.kPostJson)))
        adapter.registerData("createCachedUser", n(("createCachedUser", Fixtures.kUserAliceJson)))

        _ = try await client.queries.getCachedPost(id: "post-1")
        XCTAssertEqual(adapter.getCallCount(), 1)

        _ = try await client.mutations.createCachedUser(input: kCreateInput)
        XCTAssertEqual(adapter.getCallCount(), 2)

        _ = try await client.queries.getCachedPost(id: "post-1")
        XCTAssertEqual(adapter.getCallCount(), 2)
    }

    func test_transferPost_invalidatesBothTags() async throws {
        adapter.registerData("getCachedUser", n(("getCachedUser", Fixtures.kUserAliceJson)))
        adapter.registerData("getCachedPost", n(("getCachedPost", Fixtures.kPostJson)))
        adapter.registerData("transferPost", n(("transferPost", Fixtures.kPostJson)))

        _ = try await client.queries.getCachedUser(id: "user-1")
        _ = try await client.queries.getCachedPost(id: "post-1")
        XCTAssertEqual(adapter.getCallCount(), 2)

        _ = try await client.mutations.transferPost(postId: "post-1", newAuthorId: "user-2")
        XCTAssertEqual(adapter.getCallCount(), 3)

        _ = try await client.queries.getCachedUser(id: "user-1")
        _ = try await client.queries.getCachedPost(id: "post-1")
        XCTAssertEqual(adapter.getCallCount(), 5)
    }
}

// ── listCachedUsers ───────────────────────────────────────────────────────────

final class CacheTest_ListCachedUsers: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    func test_listCachedUsers_isCachedAfterFirstCall() async throws {
        adapter.registerData("listCachedUsers", n(("listCachedUsers", [Fixtures.kUserAliceJson])))
        _ = try await client.queries.listCachedUsers()
        _ = try await client.queries.listCachedUsers()
        XCTAssertEqual(adapter.getCallCount(), 1)
    }

    func test_createCachedUser_invalidatesListCachedUsers() async throws {
        adapter.registerData("listCachedUsers", n(("listCachedUsers", [Fixtures.kUserAliceJson])))
        adapter.registerData("createCachedUser", n(("createCachedUser", Fixtures.kUserAliceJson)))

        _ = try await client.queries.listCachedUsers()
        _ = try await client.mutations.createCachedUser(input: kCreateInput)
        _ = try await client.queries.listCachedUsers()
        XCTAssertEqual(adapter.getCallCount(), 3)
    }
}

// ── staleIfOffline ────────────────────────────────────────────────────────────

final class CacheTest_StaleIfOffline: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    func test_staleData_isReturnedWhenNetworkFails_afterTtlExpires() async throws {
        adapter.registerData("getStaleUser", n(("getStaleUser", Fixtures.kUserAliceJson)))

        _ = try await client.queries.getStaleUser(id: "user-1")
        XCTAssertEqual(adapter.getCallCount(), 1)

        // wait for TTL to expire (TTL = 1s, uses real time)
        try await Task.sleep(nanoseconds: 1_100_000_000)

        adapter.simulateFailure = true
        let res = try await client.queries.getStaleUser(id: "user-1")

        XCTAssertNotNil(res.getStaleUser)
        XCTAssertEqual(res.getStaleUser!.id, "user-1")
    }

    func test_nonStaleEntry_throwsWhenNetworkFails() async throws {
        adapter.registerData("getCachedUser", n(("getCachedUser", Fixtures.kUserAliceJson)))
        adapter.simulateFailure = true
        do {
            _ = try await client.queries.getCachedUser(id: "user-1")
            XCTFail("expected throw")
        } catch {
            // expected
        }
    }
}
