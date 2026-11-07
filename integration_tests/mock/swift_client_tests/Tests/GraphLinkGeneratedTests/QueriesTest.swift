import XCTest
@testable import GraphLinkGenerated

// ── fetchUserAndPost ─────────────────────────────────────────────────────────

final class QueriesTest_FetchUserAndPost: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerData("fetchUserAndPost", n(
            ("user", Fixtures.kUserAliceJson),
            ("post", Fixtures.kPostJson)
        ))
    }

    func test_response_isNotNull() async throws {
        let res = try await client.queries.fetchUserAndPost(userId: "user-1", postId: "post-1")
        XCTAssertNotNil(res)
    }

    func test_user_isNotNull() async throws {
        let res = try await client.queries.fetchUserAndPost(userId: "user-1", postId: "post-1")
        XCTAssertNotNil(res.user)
    }

    func test_user_hasCorrectId() async throws {
        let res = try await client.queries.fetchUserAndPost(userId: "user-1", postId: "post-1")
        XCTAssertEqual(res.user.id, "user-1")
    }

    func test_user_hasCorrectName() async throws {
        let res = try await client.queries.fetchUserAndPost(userId: "user-1", postId: "post-1")
        XCTAssertEqual(res.user.name, "Alice Smith")
    }

    func test_post_isNotNull() async throws {
        let res = try await client.queries.fetchUserAndPost(userId: "user-1", postId: "post-1")
        XCTAssertNotNil(res.post)
    }

    func test_post_hasCorrectId() async throws {
        let res = try await client.queries.fetchUserAndPost(userId: "user-1", postId: "post-1")
        XCTAssertEqual(res.post.id, "post-1")
    }

    func test_post_hasCorrectTitle() async throws {
        let res = try await client.queries.fetchUserAndPost(userId: "user-1", postId: "post-1")
        XCTAssertEqual(res.post.title, "Hello World")
    }

    func test_post_author_hasCorrectId() async throws {
        let res = try await client.queries.fetchUserAndPost(userId: "user-1", postId: "post-1")
        XCTAssertEqual(res.post.author?.id, "user-1")
    }

    func test_singleAdapterCall_forBothResolvers() async throws {
        _ = try await client.queries.fetchUserAndPost(userId: "user-1", postId: "post-1")
        XCTAssertEqual(adapter.getCallCount(), 1)
    }
}

// ── fetchUserSummary ─────────────────────────────────────────────────────────

final class QueriesTest_FetchUserSummary: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerData("fetchUserSummary", n(
            ("getUser", n(("id", "user-1"), ("name", "Alice Smith"), ("status", "ACTIVE")))
        ))
    }

    func test_response_isNotNull() async throws {
        let res = try await client.queries.fetchUserSummary(id: "user-1")
        XCTAssertNotNil(res)
    }

    func test_getUser_isNotNull() async throws {
        let res = try await client.queries.fetchUserSummary(id: "user-1")
        XCTAssertNotNil(res.getUser)
    }

    func test_getUser_isProjectedType() async throws {
        let res = try await client.queries.fetchUserSummary(id: "user-1")
        XCTAssertTrue(res.getUser is User_IdNameStatus)
    }

    func test_getUser_hasCorrectId() async throws {
        let res = try await client.queries.fetchUserSummary(id: "user-1")
        XCTAssertEqual(res.getUser.id, "user-1")
    }

    func test_getUser_hasCorrectName() async throws {
        let res = try await client.queries.fetchUserSummary(id: "user-1")
        XCTAssertEqual(res.getUser.name, "Alice Smith")
    }

    func test_getUser_status_deserializesToEnum() async throws {
        let res = try await client.queries.fetchUserSummary(id: "user-1")
        XCTAssertEqual(res.getUser.status, UserStatus.active)
    }
}

// ── runSearch ─────────────────────────────────────────────────────────────────

final class QueriesTest_RunSearch: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    func test_userResult_dispatchedCorrectly() async throws {
        adapter.registerData("runSearch", n(
            ("search", [n(
                ("__typename", "UserResult"),
                ("id", "u-1"),
                ("name", "Alice"),
                ("email", "alice@test.com")
            )])
        ))
        let results: [any SearchResult] = try await client.queries.runSearch(term: "alice").search
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0] is UserResult)
        XCTAssertEqual(results[0].id, "u-1")
        XCTAssertEqual((results[0] as! UserResult).name, "Alice")
    }

    func test_postResult_dispatchedCorrectly() async throws {
        adapter.registerData("runSearch", n(
            ("search", [n(("__typename", "PostResult"), ("id", "p-1"), ("title", "Hello"))])
        ))
        let results = try await client.queries.runSearch(term: "hello").search
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0] is PostResult)
        XCTAssertEqual(results[0].id, "p-1")
        XCTAssertEqual((results[0] as! PostResult).title, "Hello")
    }

    func test_mixedResults_dispatchedByTypename() async throws {
        adapter.registerData("runSearch", n(
            ("search", [
                n(("__typename", "UserResult"), ("id", "u-1"), ("name", "Alice"), ("email", "alice@test.com")),
                n(("__typename", "PostResult"), ("id", "p-1"), ("title", "Hello")),
            ])
        ))
        let results = try await client.queries.runSearch(term: "a").search
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0] is UserResult)
        XCTAssertTrue(results[1] is PostResult)
    }

    func test_emptyResults_returnEmptyList() async throws {
        adapter.registerData("runSearch", n(("search", [Any]())))
        let results = try await client.queries.runSearch(term: "xyz").search
        XCTAssertNotNil(results)
        XCTAssertTrue(results.isEmpty)
    }

    private func failure(_ call: () async throws -> Void) async -> String {
        do {
            try await call()
            XCTFail("expected the decode to fail")
            return ""
        } catch {
            return String(describing: error)
        }
    }

    func test_unknownTypename_throwsInsteadOfCrashing() async {
        adapter.registerData("runSearch", n(("search", [n(("__typename", "CommentResult"), ("id", "c-1"))])))
        let message = await failure { _ = try await self.client.queries.runSearch(term: "x") }
        XCTAssertTrue(message.contains("SearchResult"), message)
        XCTAssertTrue(message.contains("CommentResult"), message)
    }

    func test_absentTypename_throwsInsteadOfCrashing() async {
        adapter.registerData("runSearch", n(("search", [n(("id", "u-1"), ("name", "Alice"))])))
        let message = await failure { _ = try await self.client.queries.runSearch(term: "x") }
        XCTAssertTrue(message.contains("SearchResult") && message.contains("__typename"), message)
    }

    func test_oneBadElementFailsTheWholeCall_andTheClientKeepsWorking() async throws {
        adapter.registerData("runSearch", n(("search", [
            n(("__typename", "UserResult"), ("id", "u-1"), ("name", "Alice"), ("email", "alice@test.com")),
            n(("__typename", "Mystery"), ("id", "m-1")),
        ])))
        _ = await failure { _ = try await self.client.queries.runSearch(term: "x") }
        adapter.registerData("runSearch", n(("search", [n(("__typename", "PostResult"), ("id", "p-1"), ("title", "Hello"))])))
        let results = try await client.queries.runSearch(term: "x").search
        XCTAssertTrue(results[0] is PostResult)
    }
}

// ── fetchCachedPair ──────────────────────────────────────────────────────────

final class QueriesTest_FetchCachedPair: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerData("fetchCachedPair", n(
            ("user", Fixtures.kUserAliceJson),
            ("post", Fixtures.kPostJson)
        ))
    }

    func test_firstCall_hitsAdapter() async throws {
        _ = try await client.queries.fetchCachedPair(userId: "user-1", postId: "post-1")
        XCTAssertEqual(adapter.getCallCount(), 1)
    }

    func test_secondCall_servedFromCache() async throws {
        _ = try await client.queries.fetchCachedPair(userId: "user-1", postId: "post-1")
        _ = try await client.queries.fetchCachedPair(userId: "user-1", postId: "post-1")
        XCTAssertEqual(adapter.getCallCount(), 1)
    }

    func test_cachedResponse_user_hasCorrectId() async throws {
        _ = try await client.queries.fetchCachedPair(userId: "user-1", postId: "post-1")
        let res: FetchCachedPairResponse = try await client.queries.fetchCachedPair(userId: "user-1", postId: "post-1")
        XCTAssertEqual(res.user.id, "user-1")
    }

    func test_cachedResponse_post_hasCorrectId() async throws {
        _ = try await client.queries.fetchCachedPair(userId: "user-1", postId: "post-1")
        let res = try await client.queries.fetchCachedPair(userId: "user-1", postId: "post-1")
        XCTAssertEqual(res.post.id, "post-1")
    }

    func test_differentArgs_bypassCache() async throws {
        adapter.registerData("fetchCachedPair", n(("user", Fixtures.kUserBobJson), ("post", Fixtures.kPostJson)))
        _ = try await client.queries.fetchCachedPair(userId: "user-1", postId: "post-1")
        _ = try await client.queries.fetchCachedPair(userId: "user-2", postId: "post-1")
        XCTAssertEqual(adapter.getCallCount(), 2)
    }
}
