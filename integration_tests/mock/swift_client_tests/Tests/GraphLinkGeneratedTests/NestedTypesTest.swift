import Foundation
import XCTest
@testable import GraphLinkGenerated

final class NestedTypesTest: XCTestCase {

    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    // ── Required nested object (User.address) ─────────────────────────────────

    func test_RequiredNestedObject_address_isNotNull() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserAliceJson)))
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertNotNil(res.getUser.address)
    }

    func test_RequiredNestedObject_address_hasCorrectStreet() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserAliceJson)))
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertEqual(res.getUser.address.street, "123 Main St")
    }

    func test_RequiredNestedObject_address_hasCorrectCity() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserAliceJson)))
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertEqual(res.getUser.address.city, "Springfield")
    }

    func test_RequiredNestedObject_address_hasCorrectCountry() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserAliceJson)))
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertEqual(res.getUser.address.country, "US")
    }

    func test_RequiredNestedObject_address_hasCorrectZip() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserAliceJson)))
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertEqual(res.getUser.address.zip, "12345")
    }

    func test_RequiredNestedObject_address_deserializesToAddressType() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserAliceJson)))
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertTrue(res.getUser.address is Address)
    }

    // ── Multi-level nesting (Post → User) ─────────────────────────────────────

    func test_MultiLevelNesting_post_isNotNull() async throws {
        adapter.registerData("getPost", n(("getPost", Fixtures.kPostJson)))
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertNotNil(res.getPost)
    }

    func test_MultiLevelNesting_post_deserializesToPostType() async throws {
        adapter.registerData("getPost", n(("getPost", Fixtures.kPostJson)))
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertTrue(res.getPost is Post)
    }

    func test_MultiLevelNesting_post_hasCorrectTitle() async throws {
        adapter.registerData("getPost", n(("getPost", Fixtures.kPostJson)))
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertEqual(res.getPost.title, "Hello World")
    }

    func test_MultiLevelNesting_post_author_isNotNull() async throws {
        adapter.registerData("getPost", n(("getPost", Fixtures.kPostJson)))
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertNotNil(res.getPost.author)
    }

    func test_MultiLevelNesting_post_author_deserializesToFragmentType() async throws {
        adapter.registerData("getPost", n(("getPost", Fixtures.kPostJson)))
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertTrue(res.getPost.author is User)
    }

    func test_MultiLevelNesting_post_author_hasCorrectId() async throws {
        adapter.registerData("getPost", n(("getPost", Fixtures.kPostJson)))
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertEqual(res.getPost.author?.id, "user-1")
    }

    func test_MultiLevelNesting_post_author_status_deserializesToEnum() async throws {
        adapter.registerData("getPost", n(("getPost", Fixtures.kPostJson)))
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertEqual(res.getPost.author?.status, UserStatus.active)
    }

    func test_MultiLevelNesting_post_author_address_city_isAccessible() async throws {
        adapter.registerData("getPost", n(("getPost", Fixtures.kPostJson)))
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertEqual(res.getPost.author?.address.city, "Springfield")
    }

    func test_MultiLevelNesting_post_viewCount_deserializesToInt() async throws {
        adapter.registerData("getPost", n(("getPost", Fixtures.kPostJson)))
        let res = try await client.queries.getPost(id: "post-1")
        XCTAssertEqual(res.getPost.viewCount, 128)
    }

    // ── @glSkipOnClient — server-only field silently ignored ──────────────────

    func test_SkipOnClientField_auditEntry_withoutInternalNote_deserializesCorrectly() async throws {
        adapter.registerData("getAuditEntry", n(("getAuditEntry", Fixtures.kAuditEntryJson)))
        let entry: AuditEntry = try await client.queries.getAuditEntry(id: "audit-1").getAuditEntry
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry.id, "audit-1")
        XCTAssertEqual(entry.action, "LOGIN")
        XCTAssertEqual(entry.performedBy, "user-1")
    }

    func test_SkipOnClientField_auditEntry_withExtraServerField_isIgnoredSilently() async throws {
        adapter.registerData("getAuditEntry", n(("getAuditEntry", Fixtures.kAuditEntryWithExtraJson)))
        let entry: AuditEntry = try await client.queries.getAuditEntry(id: "audit-2").getAuditEntry
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry.id, "audit-2")
        XCTAssertEqual(entry.action, "LOGOUT")
    }
}
