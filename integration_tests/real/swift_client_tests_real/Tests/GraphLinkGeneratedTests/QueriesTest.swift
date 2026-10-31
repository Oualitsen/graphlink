import XCTest
@testable import GraphLinkGenerated

// ── fetchUserAndPost — multi-resolver, single round-trip ────────────────────

final class QueriesTest_FetchUserAndPost: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
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
}

// ── fetchUserSummary — partial projection ────────────────────────────────────

final class QueriesTest_FetchUserSummary: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
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

// ── runSearch — interface dispatch via __typename ────────────────────────────

final class QueriesTest_RunSearch: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_results_containUserResult() async throws {
        let results = try await client.queries.runSearch(term: "alice").search
        XCTAssertNotNil(results)
        XCTAssertTrue(results.contains { $0 is UserResult })
    }

    func test_results_containPostResult() async throws {
        let results = try await client.queries.runSearch(term: "alice").search
        XCTAssertNotNil(results)
        XCTAssertTrue(results.contains { $0 is PostResult })
    }

    func test_userResult_hasCorrectId() async throws {
        let results = try await client.queries.runSearch(term: "alice").search
        let user = results.compactMap { $0 as? UserResult }.first
        XCTAssertNotNil(user)
        XCTAssertEqual(user?.id, "user-1")
        XCTAssertEqual(user?.name, "Alice Smith")
    }

    func test_postResult_hasCorrectId() async throws {
        let results = try await client.queries.runSearch(term: "alice").search
        let post = results.compactMap { $0 as? PostResult }.first
        XCTAssertNotNil(post)
        XCTAssertEqual(post?.id, "post-1")
    }
}
