import Foundation
import XCTest
@testable import GraphLinkGenerated

final class NullabilityTest: XCTestCase {

    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    // ── Non-nullable query return type ────────────────────────────────────────

    func test_NonNullableQueryReturn_getUser_returnsNonNullUser() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserAliceJson)))
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertNotNil(res.getUser)
    }

    func test_NonNullableQueryReturn_getUser_hasCorrectId() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserAliceJson)))
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertEqual(res.getUser.id, "user-1")
    }

    // ── Nullable query return type — null ─────────────────────────────────────

    func test_NullableQueryReturn_Null_findUser_returnsNull_whenServerReturnsNull() async throws {
        adapter.registerData("findUser", n(("findUser", nil)))
        let res = try await client.queries.findUser(id: "user-99")
        XCTAssertNil(res.findUser)
    }

    // ── Nullable query return type — present ──────────────────────────────────

    func test_NullableQueryReturn_Present_findUser_returnsUser_whenServerReturnsData() async throws {
        adapter.registerData("findUser", n(("findUser", Fixtures.kUserAliceJson)))
        let res = try await client.queries.findUser(id: "user-1")
        XCTAssertNotNil(res.findUser)
        XCTAssertEqual(res.findUser!.id, "user-1")
    }

    // ── Nullable nested object — null ─────────────────────────────────────────

    func test_NullableNestedObject_Null_billingAddress_isNull_whenAbsent() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserAliceJson)))
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertNil(res.getUser.billingAddress)
    }

    // ── Nullable nested object — present ──────────────────────────────────────

    func test_NullableNestedObject_Present_billingAddress_isNotNull_whenPresent() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserBobJson)))
        let res = try await client.queries.getUser(id: "user-2")
        XCTAssertNotNil(res.getUser.billingAddress)
    }

    func test_NullableNestedObject_Present_billingAddress_hasCorrectCity() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserBobJson)))
        let res = try await client.queries.getUser(id: "user-2")
        XCTAssertEqual(res.getUser.billingAddress!.city, "Capital City")
    }

    // ── Nullable scalar on nested type ────────────────────────────────────────

    func test_NullableScalarOnNestedType_address_zip_isNull_whenAbsent() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserBobJson)))
        let res = try await client.queries.getUser(id: "user-2")
        XCTAssertNil(res.getUser.address.zip)
    }

    func test_NullableScalarOnNestedType_address_zip_isPresent_whenSet() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserAliceJson)))
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertEqual(res.getUser.address.zip, "12345")
    }

    // ── Nullable list field ───────────────────────────────────────────────────

    func test_NullableListField_scores_isNull_whenAbsent() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserBobJson)))
        let res = try await client.queries.getUser(id: "user-2")
        XCTAssertNil(res.getUser.scores)
    }

    func test_NullableListField_scores_hasList_whenPresent() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserAliceJson)))
        let res = try await client.queries.getUser(id: "user-1")
        let scores = res.getUser.scores
        XCTAssertNotNil(scores)
        XCTAssertEqual(scores!.count, 3)
    }

    // ── Nullable coAuthor on Post ─────────────────────────────────────────────

    func test_NullableCoAuthor_coAuthor_isNull_whenAbsent() async throws {
        adapter.registerData("getPost", n(("getPost", Fixtures.kPostJson)))
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertNil(res.getPost.coAuthor)
    }

    func test_NullableCoAuthor_coAuthor_isNotNull_whenPresent() async throws {
        adapter.registerData("getPost", n(("getPost", Fixtures.kPostWithCoAuthorJson)))
        let res = try await client.queries.getPost(id: "post-2")
        let coAuthor = res.getPost.coAuthor
        XCTAssertNotNil(coAuthor)
        XCTAssertEqual(coAuthor!.id, "user-2")
    }
}
