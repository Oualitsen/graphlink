import Foundation
import XCTest
@testable import GraphLinkGenerated

final class ListsTest: XCTestCase {

    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    // ── Non-nullable list of objects ──────────────────────────────────────────

    func test_NonNullableListOfObjects_listUsers_isNotNull() async throws {
        adapter.registerData("listUsers", n(("listUsers", [Fixtures.kUserAliceJson, Fixtures.kUserBobJson])))
        let res = try await client.queries.listUsers()
        XCTAssertNotNil(res.listUsers)
    }

    func test_NonNullableListOfObjects_listUsers_hasTwoItems() async throws {
        adapter.registerData("listUsers", n(("listUsers", [Fixtures.kUserAliceJson, Fixtures.kUserBobJson])))
        let res = try await client.queries.listUsers()
        XCTAssertEqual(res.listUsers.count, 2)
    }

    func test_NonNullableListOfObjects_listUsers_firstItem_isUserType() async throws {
        adapter.registerData("listUsers", n(("listUsers", [Fixtures.kUserAliceJson, Fixtures.kUserBobJson])))
        let res = try await client.queries.listUsers()
        XCTAssertTrue(res.listUsers[0] is User)
    }

    func test_NonNullableListOfObjects_listUsers_firstItem_hasCorrectId() async throws {
        adapter.registerData("listUsers", n(("listUsers", [Fixtures.kUserAliceJson, Fixtures.kUserBobJson])))
        let res = try await client.queries.listUsers()
        XCTAssertEqual(res.listUsers[0].id, "user-1")
    }

    func test_NonNullableListOfObjects_listUsers_secondItem_hasCorrectId() async throws {
        adapter.registerData("listUsers", n(("listUsers", [Fixtures.kUserAliceJson, Fixtures.kUserBobJson])))
        let res = try await client.queries.listUsers()
        XCTAssertEqual(res.listUsers[1].id, "user-2")
    }

    func test_NonNullableListOfObjects_listUsers_items_haveDeserializedEnums() async throws {
        adapter.registerData("listUsers", n(("listUsers", [Fixtures.kUserAliceJson, Fixtures.kUserBobJson])))
        let users = try await client.queries.listUsers().listUsers
        XCTAssertEqual(users[0].status, UserStatus.active)
        XCTAssertEqual(users[1].status, UserStatus.inactive)
    }

    // ── Empty list ────────────────────────────────────────────────────────────

    func test_EmptyList_listUsers_empty_returnsEmptyList() async throws {
        adapter.registerData("listUsers", n(("listUsers", [Any]())))
        let res = try await client.queries.listUsers()
        XCTAssertNotNil(res.listUsers)
        XCTAssertTrue(res.listUsers.isEmpty)
    }

    // ── List with nullable item fields ────────────────────────────────────────

    func test_ListWithNullableItemFields_getTags_hasTwoItems() async throws {
        adapter.registerData("getTags", n(("getTags", Fixtures.kTagsJson)))
        let res = try await client.queries.getTags()
        XCTAssertEqual(res.getTags.count, 2)
    }

    func test_ListWithNullableItemFields_getTags_firstItem_isTagType() async throws {
        adapter.registerData("getTags", n(("getTags", Fixtures.kTagsJson)))
        let res = try await client.queries.getTags()
        XCTAssertTrue(res.getTags[0] is Tag)
    }

    func test_ListWithNullableItemFields_getTags_firstItem_hasColor() async throws {
        adapter.registerData("getTags", n(("getTags", Fixtures.kTagsJson)))
        let res = try await client.queries.getTags()
        XCTAssertEqual(res.getTags[0].color, "#0175C2")
    }

    func test_ListWithNullableItemFields_getTags_secondItem_colorIsNull() async throws {
        adapter.registerData("getTags", n(("getTags", Fixtures.kTagsJson)))
        let res = try await client.queries.getTags()
        XCTAssertNil(res.getTags[1].color)
    }

    func test_ListWithNullableItemFields_getTags_secondItem_hasLabel() async throws {
        adapter.registerData("getTags", n(("getTags", Fixtures.kTagsJson)))
        let res = try await client.queries.getTags()
        XCTAssertEqual(res.getTags[1].label, "graphql")
    }

    // ── List of scalars on a type ─────────────────────────────────────────────

    func test_ListOfScalars_tags_onUser_isListOfStrings() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserAliceJson)))
        let tags: [String] = try await client.queries.getUser(id: "user-1").getUser.tags
        XCTAssertNotNil(tags)
        XCTAssertEqual(tags.count, 2)
        XCTAssertEqual(tags[0], "admin")
        XCTAssertEqual(tags[1], "beta")
    }

    func test_ListOfScalars_tags_empty_returnsEmptyList() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserBobJson)))
        let tags = try await client.queries.getUser(id: "user-2").getUser.tags
        XCTAssertNotNil(tags)
        XCTAssertTrue(tags.isEmpty)
    }

    func test_ListOfScalars_scores_onUser_isListOfInts() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserAliceJson)))
        let scores: [Int]? = try await client.queries.getUser(id: "user-1").getUser.scores
        XCTAssertNotNil(scores)
        XCTAssertEqual(scores!, [10, 20, 30])
    }

    // ── searchUsers ───────────────────────────────────────────────────────────

    func test_SearchUsers_searchUsers_sendsNameAndLimit() async throws {
        adapter.registerData("searchUsers", n(("searchUsers", [Fixtures.kUserAliceJson])))
        _ = try await client.queries.searchUsers(name: "Alice", limit: 10)
        let vars = adapter.getLastCall()!.variables
        XCTAssertEqual(vars["name"] as? String, "Alice")
        XCTAssertEqual(vars["limit"] as? Int, 10)
    }

    func test_SearchUsers_searchUsers_returnsMatchingUsers() async throws {
        adapter.registerData("searchUsers", n(("searchUsers", [Fixtures.kUserAliceJson])))
        let res = try await client.queries.searchUsers(name: "Alice", limit: 10)
        XCTAssertNotNil(res.searchUsers)
        XCTAssertEqual(res.searchUsers.count, 1)
        XCTAssertEqual(res.searchUsers[0].id, "user-1")
    }
}
