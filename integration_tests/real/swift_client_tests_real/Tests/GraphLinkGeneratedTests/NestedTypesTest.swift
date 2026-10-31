import Foundation
import XCTest
@testable import GraphLinkGenerated

// ── Required nested object (User.address) ─────────────────────────────────

final class NestedTypesTest_RequiredNestedObject: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_address_isNotNull() async throws {
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertNotNil(res.getUser.address)
    }

    func test_address_hasCorrectStreet() async throws {
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertEqual(res.getUser.address.street, "123 Main St")
    }

    func test_address_hasCorrectCity() async throws {
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertEqual(res.getUser.address.city, "Springfield")
    }

    func test_address_hasCorrectCountry() async throws {
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertEqual(res.getUser.address.country, "US")
    }

    func test_address_hasCorrectZip() async throws {
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertEqual(res.getUser.address.zip, "12345")
    }

    func test_address_deserializesToAddressType() async throws {
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertTrue(res.getUser.address is Address)
    }
}

// ── Multi-level nesting (Post → User) ─────────────────────────────────────

final class NestedTypesTest_MultiLevelNesting: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_post_isNotNull() async throws {
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertNotNil(res.getPost)
    }

    func test_post_deserializesToPostType() async throws {
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertTrue(res.getPost is Post)
    }

    func test_post_hasCorrectTitle() async throws {
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertEqual(res.getPost.title, "Hello World")
    }

    func test_post_author_isNotNull() async throws {
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertNotNil(res.getPost.author)
    }

    func test_post_author_deserializesToFragmentType() async throws {
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertTrue(res.getPost.author is User)
    }

    func test_post_author_hasCorrectId() async throws {
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertEqual(res.getPost.author?.id, "user-1")
    }

    func test_post_author_status_deserializesToEnum() async throws {
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertEqual(res.getPost.author?.status, UserStatus.active)
    }

    func test_post_author_address_city_isAccessible() async throws {
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertEqual(res.getPost.author?.address.city, "Springfield")
    }

    func test_post_viewCount_deserializesToInt() async throws {
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertEqual(res.getPost.viewCount, 128)
    }
}

// ── @glSkipOnClient — server-only field silently ignored ──────────────────

final class NestedTypesTest_SkipOnClientField: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_auditEntry_deserializesCorrectly() async throws {
        let entry = try await client.queries.getAuditEntry(id: "audit-1").getAuditEntry
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry.id, "audit-1")
        XCTAssertEqual(entry.action, "LOGIN")
        XCTAssertEqual(entry.performedBy, "user-1")
    }

    func test_auditEntry_withExtraServerField_isIgnoredSilently() async throws {
        let entry = try await client.queries.getAuditEntry(id: "audit-2").getAuditEntry
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry.id, "audit-2")
        XCTAssertEqual(entry.action, "LOGOUT")
    }
}
