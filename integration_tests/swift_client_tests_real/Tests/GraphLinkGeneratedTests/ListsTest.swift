import Foundation
import XCTest
@testable import GraphLinkGenerated

// ── Non-nullable list of objects ──────────────────────────────────────────

final class ListsTest_NonNullableListOfObjects: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_listUsers_isNotNull() async throws {
        let res = try await client.queries.listUsers()
        XCTAssertNotNil(res.listUsers)
    }

    func test_listUsers_hasTwoItems() async throws {
        let res = try await client.queries.listUsers()
        XCTAssertEqual(res.listUsers.count, 2)
    }

    func test_listUsers_firstItem_isUserType() async throws {
        let res = try await client.queries.listUsers()
        XCTAssertTrue(res.listUsers[0] is User)
    }

    func test_listUsers_firstItem_hasCorrectId() async throws {
        let res = try await client.queries.listUsers()
        XCTAssertEqual(res.listUsers[0].id, "user-1")
    }

    func test_listUsers_secondItem_hasCorrectId() async throws {
        let res = try await client.queries.listUsers()
        XCTAssertEqual(res.listUsers[1].id, "user-2")
    }

    func test_listUsers_items_haveDeserializedEnums() async throws {
        let users = try await client.queries.listUsers().listUsers
        XCTAssertEqual(users[0].status, UserStatus.active)
        XCTAssertEqual(users[1].status, UserStatus.inactive)
    }
}

// ── List with nullable item fields ────────────────────────────────────────

final class ListsTest_ListWithNullableItemFields: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_getTags_hasTwoItems() async throws {
        let res = try await client.queries.getTags()
        XCTAssertEqual(res.getTags.count, 2)
    }

    func test_getTags_firstItem_isTagType() async throws {
        let res = try await client.queries.getTags()
        XCTAssertTrue(res.getTags[0] is Tag)
    }

    func test_getTags_firstItem_hasColor() async throws {
        let res = try await client.queries.getTags()
        XCTAssertEqual(res.getTags[0].color, "#0175C2")
    }

    func test_getTags_secondItem_colorIsNull() async throws {
        let res = try await client.queries.getTags()
        XCTAssertNil(res.getTags[1].color)
    }

    func test_getTags_secondItem_hasLabel() async throws {
        let res = try await client.queries.getTags()
        XCTAssertEqual(res.getTags[1].label, "graphql")
    }
}

// ── List of scalars on a type ─────────────────────────────────────────────

final class ListsTest_ListOfScalars: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_tags_onAlice_isListOfStrings() async throws {
        let tags = try await client.queries.getUser(id: "user-1").getUser.tags
        XCTAssertNotNil(tags)
        XCTAssertEqual(tags.count, 2)
        XCTAssertEqual(tags[0], "admin")
        XCTAssertEqual(tags[1], "beta")
    }

    func test_tags_onBob_isEmpty() async throws {
        let tags = try await client.queries.getUser(id: "user-2").getUser.tags
        XCTAssertNotNil(tags)
        XCTAssertTrue(tags.isEmpty)
    }

    func test_scores_onAlice_isListOfInts() async throws {
        let scores = try await client.queries.getUser(id: "user-1").getUser.scores
        XCTAssertNotNil(scores)
        XCTAssertEqual(scores!, [10, 20, 30])
    }

    func test_scores_onBob_isNull() async throws {
        let scores = try await client.queries.getUser(id: "user-2").getUser.scores
        XCTAssertNil(scores)
    }
}

// ── searchUsers ───────────────────────────────────────────────────────────

final class ListsTest_SearchUsers: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_searchUsers_returnsMatchingUsers() async throws {
        let res = try await client.queries.searchUsers(name: "Alice", limit: 10)
        XCTAssertNotNil(res.searchUsers)
        XCTAssertFalse(res.searchUsers.isEmpty)
        XCTAssertEqual(res.searchUsers[0].id, "user-1")
    }

    func test_searchUsers_withLimit_respectsLimit() async throws {
        let res = try await client.queries.searchUsers(name: "", limit: 1)
        XCTAssertNotNil(res.searchUsers)
        XCTAssertLessThanOrEqual(res.searchUsers.count, 1)
    }
}
