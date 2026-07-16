import Foundation
import XCTest
@testable import GraphLinkGenerated

// ── Enum deserialization in response ──────────────────────────────────────

final class EnumsTest_EnumDeserialization: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testStatus_deserializesToUserStatus_ACTIVE() async throws {
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertEqual(res.getUser.status, UserStatus.active)
    }

    func testStatus_deserializesToUserStatus_INACTIVE() async throws {
        let res = try await client.queries.getUser(id: "user-2")
        XCTAssertEqual(res.getUser.status, UserStatus.inactive)
    }

    func testPriority_deserializesToPriority_HIGH() async throws {
        let priority = try await client.queries.getUser(id: "user-1").getUser.priority
        XCTAssertEqual(priority, Priority.high)
    }

    func testPriority_isNull_whenAbsent() async throws {
        let res = try await client.queries.getUser(id: "user-2")
        XCTAssertNil(res.getUser.priority)
    }
}

// ── Enum as query argument ────────────────────────────────────────────────

final class EnumsTest_EnumAsQueryArgument: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func testResponse_containsDeserializedUsers() async throws {
        let res = try await client.queries.listUsersByStatus(status: .active)
        XCTAssertNotNil(res.listUsersByStatus)
        XCTAssertTrue(!res.listUsersByStatus.isEmpty)
        XCTAssertTrue(res.listUsersByStatus.allSatisfy { $0.status == UserStatus.active })
    }
}

// ── All enum values round-trip ────────────────────────────────────────────

final class EnumsTest_EnumRoundTrip: XCTestCase {

    func testUserStatus_ACTIVE_roundTrips() {
        XCTAssertEqual(UserStatus.active.toJson(), "ACTIVE")
        XCTAssertEqual(UserStatus.fromJson("ACTIVE"), UserStatus.active)
    }

    func testUserStatus_INACTIVE_roundTrips() {
        XCTAssertEqual(UserStatus.inactive.toJson(), "INACTIVE")
        XCTAssertEqual(UserStatus.fromJson("INACTIVE"), UserStatus.inactive)
    }

    func testUserStatus_SUSPENDED_roundTrips() {
        XCTAssertEqual(UserStatus.suspended.toJson(), "SUSPENDED")
        XCTAssertEqual(UserStatus.fromJson("SUSPENDED"), UserStatus.suspended)
    }

    func testPriority_LOW_roundTrips() {
        XCTAssertEqual(Priority.low.toJson(), "LOW")
        XCTAssertEqual(Priority.fromJson("LOW"), Priority.low)
    }

    func testPriority_CRITICAL_roundTrips() {
        XCTAssertEqual(Priority.critical.toJson(), "CRITICAL")
        XCTAssertEqual(Priority.fromJson("CRITICAL"), Priority.critical)
    }
}
