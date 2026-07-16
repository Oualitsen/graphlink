import XCTest
@testable import GraphLinkGenerated

// ── User → posts → post.author (cycle broken) ──────────────────────────────

final class CycleTest_UserWithPosts: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserWithPostsJson)))
    }

    func test_user_posts_isNotNull() async throws {
        let user = try await client.queries.getUser(id: "user-1").getUser
        XCTAssertNotNil(user.posts)
    }

    func test_user_posts_hasOneEntry() async throws {
        let user = try await client.queries.getUser(id: "user-1").getUser
        XCTAssertEqual(user.posts!.count, 1)
    }

    func test_user_posts_firstEntry_isPostType() async throws {
        let user = try await client.queries.getUser(id: "user-1").getUser
        XCTAssertTrue(user.posts![0] is Post)
    }

    func test_user_posts_firstEntry_hasCorrectId() async throws {
        let user = try await client.queries.getUser(id: "user-1").getUser
        XCTAssertEqual(user.posts![0].id, "post-10")
    }

    func test_user_posts_firstEntry_hasCorrectTitle() async throws {
        let user = try await client.queries.getUser(id: "user-1").getUser
        XCTAssertEqual(user.posts![0].title, "Cyclic Post")
    }

    func test_user_posts_author_isTruncatedUserType() async throws {
        let user = try await client.queries.getUser(id: "user-1").getUser
        XCTAssertTrue(user.posts![0].author is User?)
    }

    func test_user_posts_author_hasCorrectId() async throws {
        let user = try await client.queries.getUser(id: "user-1").getUser
        XCTAssertEqual(user.posts![0].author?.id, "user-1")
    }

    func test_user_posts_author_address_isNotNull() async throws {
        let user = try await client.queries.getUser(id: "user-1").getUser
        XCTAssertNotNil(user.posts![0].author?.address)
    }

    func test_user_posts_author_address_city_isAccessible() async throws {
        let user = try await client.queries.getUser(id: "user-1").getUser
        XCTAssertEqual(user.posts![0].author?.address.city, "Springfield")
    }
}

// ── User with posts: null ───────────────────────────────────────────────────

final class CycleTest_UserNullPosts: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    func test_user_posts_isNull_whenNotPopulated() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserAliceJson)))
        let user: User = try await client.queries.getUser(id: "user-1").getUser
        XCTAssertNil(user.posts)
    }
}

// ── Post → author (truncated user) ──────────────────────────────────────────

final class CycleTest_PostCycleAuthor: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerData("getPost", n(("getPost", Fixtures.kPostWithAuthorCycleJson)))
    }

    func test_post_author_isTruncatedUserType() async throws {
        let post = try await client.queries.getPost(id: "post-10").getPost
        XCTAssertTrue(post.author is User?)
    }

    func test_post_author_hasCorrectId() async throws {
        let post = try await client.queries.getPost(id: "post-10").getPost
        XCTAssertEqual(post.author?.id, "user-1")
    }

    func test_post_author_address_isNotNull() async throws {
        let post = try await client.queries.getPost(id: "post-10").getPost
        XCTAssertNotNil(post.author?.address)
    }

    func test_post_coAuthor_isNull() async throws {
        let post = try await client.queries.getPost(id: "post-10").getPost
        XCTAssertNil(post.coAuthor)
    }
}

// ── Post with coAuthor ──────────────────────────────────────────────────────

final class CycleTest_PostWithCoAuthor: XCTestCase {
    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
        adapter.registerData("getPost", n(("getPost", Fixtures.kPostWithCoAuthorJson)))
    }

    func test_post_coAuthor_isNotNull() async throws {
        let post = try await client.queries.getPost(id: "post-2").getPost
        XCTAssertNotNil(post.coAuthor)
    }

    func test_post_coAuthor_isTruncatedUserType() async throws {
        let post = try await client.queries.getPost(id: "post-2").getPost
        XCTAssertTrue(post.coAuthor is User?)
    }

    func test_post_coAuthor_hasCorrectId() async throws {
        let post = try await client.queries.getPost(id: "post-2").getPost
        XCTAssertEqual(post.coAuthor!.id, "user-2")
    }

    func test_post_author_and_coAuthor_haveDifferentIds() async throws {
        let post: Post = try await client.queries.getPost(id: "post-2").getPost
        XCTAssertNotEqual(post.author?.id, post.coAuthor!.id)
    }
}
