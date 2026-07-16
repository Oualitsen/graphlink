import Foundation
import XCTest
@testable import GraphLinkGenerated

/// End-to-end coverage for identifier normalization.
///
/// Schema uses non-canonical field casing:
///   - FirstName  → Swift codeName: firstName
///   - last_name  → Swift codeName: lastName
///   - USER_AGE   → Swift codeName: userAge
///   - event_type → Swift codeName: eventType
///
/// Enum values use camelCase in Swift (wire: pending → pending,
/// in_progress → inProgress, completed_ok → completedOk). Wire names are
/// always used in the GraphQL request and toJson/fromJson.

// ── EventType enum round-trip ─────────────────────────────────────────────

final class NormalizationTest_EventTypeRoundTrip: XCTestCase {
    func test_pending_roundTrips() {
        XCTAssertEqual(EventType.pending.toJson(), "pending")
        XCTAssertEqual(EventType.fromJson("pending"), EventType.pending)
    }

    func test_inProgress_roundTrips() {
        XCTAssertEqual(EventType.inProgress.toJson(), "in_progress")
        XCTAssertEqual(EventType.fromJson("in_progress"), EventType.inProgress)
    }

    func test_completedOk_roundTrips() {
        XCTAssertEqual(EventType.completedOk.toJson(), "completed_ok")
        XCTAssertEqual(EventType.fromJson("completed_ok"), EventType.completedOk)
    }
}

// ── Field normalization — getNormalizedRecord ─────────────────────────────

final class NormalizationTest_FieldNormalization: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_firstName_isAccessible_wireNameFirstName() async throws {
        let res = try await client.queries.getNormalizedRecord(id: "rec-1")
        XCTAssertEqual(res.getNormalizedRecord.firstName, "Alice")
    }

    func test_lastName_isAccessible_wireNameLastName() async throws {
        let res = try await client.queries.getNormalizedRecord(id: "rec-1")
        XCTAssertEqual(res.getNormalizedRecord.lastName, "Smith")
    }

    func test_userAge_isAccessible_wireNameUSER_AGE() async throws {
        let res = try await client.queries.getNormalizedRecord(id: "rec-1")
        XCTAssertEqual(res.getNormalizedRecord.userAge, 30)
    }

    func test_eventType_isScreamingSnake_wireNameIn_progress() async throws {
        let res = try await client.queries.getNormalizedRecord(id: "rec-1")
        XCTAssertEqual(res.getNormalizedRecord.eventType, EventType.inProgress)
    }
}

// ── Input normalization — createNormalizedRecord ──────────────────────────

final class NormalizationTest_InputNormalization: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        client = Fixtures.newRealClient()
    }

    func test_normalizedInputFields_roundTripThroughServer() async throws {
        let input = NormalizedInput(
            firstName: "Bob",
            lastName: "Jones",
            eventType: .completedOk
        )
        let res = try await client.mutations.createNormalizedRecord(input: input)
        XCTAssertEqual(res.createNormalizedRecord.firstName, "Bob")
        XCTAssertEqual(res.createNormalizedRecord.lastName, "Jones")
        XCTAssertEqual(res.createNormalizedRecord.eventType, EventType.completedOk)
    }
}
