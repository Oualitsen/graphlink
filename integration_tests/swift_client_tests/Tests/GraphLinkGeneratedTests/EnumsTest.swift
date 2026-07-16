import Foundation
import XCTest
@testable import GraphLinkGenerated

final class EnumsTest: XCTestCase {

    var adapter: MockAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        adapter = MockAdapter()
        client = Fixtures.newClient(adapter, MockWebSocketAdapter())
    }

    // ── Enum deserialization in response ──────────────────────────────────────

    func test_EnumDeserialization_status_deserializesToUserStatus_ACTIVE() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserAliceJson)))
        let res = try await client.queries.getUser(id: "user-1")
        XCTAssertEqual(res.getUser.status, UserStatus.active)
    }

    func test_EnumDeserialization_status_deserializesToUserStatus_INACTIVE() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserBobJson)))
        let res = try await client.queries.getUser(id: "user-2")
        XCTAssertEqual(res.getUser.status, UserStatus.inactive)
    }

    func test_EnumDeserialization_priority_deserializesToPriority_HIGH() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserAliceJson)))
        let res = try await client.queries.getUser(id: "user-1")
        let priority = res.getUser.priority
        XCTAssertEqual(priority, Priority.high)
    }

    func test_EnumDeserialization_priority_isNull_whenAbsent() async throws {
        adapter.registerData("getUser", n(("getUser", Fixtures.kUserBobJson)))
        let res = try await client.queries.getUser(id: "user-2")
        XCTAssertNil(res.getUser.priority)
    }

    // ── Enum as query argument ────────────────────────────────────────────────

    func test_EnumAsQueryArgument_enumArg_isSentAsStringInVariables() async throws {
        adapter.registerData("listUsersByStatus", n(("listUsersByStatus", [Fixtures.kUserAliceJson])))
        _ = try await client.queries.listUsersByStatus(status: .active)
        XCTAssertEqual(adapter.getLastCall()?.variables["status"] as? String, "ACTIVE")
    }

    func test_EnumAsQueryArgument_operationName_isListUsersByStatus() async throws {
        adapter.registerData("listUsersByStatus", n(("listUsersByStatus", [Fixtures.kUserAliceJson])))
        _ = try await client.queries.listUsersByStatus(status: .active)
        XCTAssertEqual(adapter.getLastCall()?.operationName, "listUsersByStatus")
    }

    func test_EnumAsQueryArgument_response_containsDeserializedUsers() async throws {
        adapter.registerData("listUsersByStatus", n(("listUsersByStatus", [Fixtures.kUserAliceJson])))
        let res = try await client.queries.listUsersByStatus(status: .active)
        XCTAssertNotNil(res.listUsersByStatus)
        XCTAssertEqual(res.listUsersByStatus.count, 1)
        XCTAssertEqual(res.listUsersByStatus[0].status, UserStatus.active)
    }

    // ── All enum values round-trip ────────────────────────────────────────────

    func test_EnumRoundTrip_userStatus_ACTIVE_roundTrips() {
        XCTAssertEqual(UserStatus.active.toJson(), "ACTIVE")
        XCTAssertEqual(UserStatus.fromJson("ACTIVE"), UserStatus.active)
    }

    func test_EnumRoundTrip_userStatus_INACTIVE_roundTrips() {
        XCTAssertEqual(UserStatus.inactive.toJson(), "INACTIVE")
        XCTAssertEqual(UserStatus.fromJson("INACTIVE"), UserStatus.inactive)
    }

    func test_EnumRoundTrip_userStatus_SUSPENDED_roundTrips() {
        XCTAssertEqual(UserStatus.suspended.toJson(), "SUSPENDED")
        XCTAssertEqual(UserStatus.fromJson("SUSPENDED"), UserStatus.suspended)
    }

    func test_EnumRoundTrip_priority_LOW_roundTrips() {
        XCTAssertEqual(Priority.low.toJson(), "LOW")
        XCTAssertEqual(Priority.fromJson("LOW"), Priority.low)
    }

    func test_EnumRoundTrip_priority_CRITICAL_roundTrips() {
        XCTAssertEqual(Priority.critical.toJson(), "CRITICAL")
        XCTAssertEqual(Priority.fromJson("CRITICAL"), Priority.critical)
    }
}
