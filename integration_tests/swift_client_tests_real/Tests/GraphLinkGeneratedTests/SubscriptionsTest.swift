import Foundation
import XCTest
@testable import GraphLinkGenerated

/// Real-server subscription tests. Unlike the mock tier, there is no
/// `MockWebSocketAdapter.deliverNext` — the Spring server pushes its fixed
/// fixture events (`Flux.just(...)`) as soon as the `graphql-transport-ws`
/// handshake completes and the subscription is registered, so no separate
/// triggering mutation is required. We still race each collection against a
/// generous timeout since this is a real network round-trip.
private func collect<T>(_ stream: AsyncThrowingStream<T, Error>, count: Int, timeout: TimeInterval = 10) async throws -> [T] {
    try await withThrowingTaskGroup(of: [T].self) { group in
        group.addTask {
            var events: [T] = []
            for try await value in stream {
                events.append(value)
                if events.count >= count { break }
            }
            return events
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw GraphLinkTestTimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private struct GraphLinkTestTimeoutError: Error {}

// ── userCreated ────────────────────────────────────────────────────────────

final class SubscriptionsTest_UserCreated: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func test_firstEvent_isAlice() async throws {
        let events = try await collect(client.subscriptions.userCreated(), count: 1)
        XCTAssertEqual(events[0].userCreated.id, "user-1")
    }

    func test_firstEvent_name_isAliceSmith() async throws {
        let events = try await collect(client.subscriptions.userCreated(), count: 1)
        XCTAssertEqual(events[0].userCreated.name, "Alice Smith")
    }

    func test_firstEvent_status_deserializesToEnum() async throws {
        let events = try await collect(client.subscriptions.userCreated(), count: 1)
        XCTAssertEqual(events[0].userCreated.status, .active)
    }

    func test_bothEvents_deliveredInOrder() async throws {
        let events = try await collect(client.subscriptions.userCreated(), count: 2)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].userCreated.id, "user-1")
        XCTAssertEqual(events[1].userCreated.id, "user-2")
    }
}

// ── MultipleIdenticalSubscriptions ────────────────────────────────────────────
// Same operation + same args collected concurrently — each call gets its own
// UUID so both flows receive independent events from the server.

final class SubscriptionsTest_MultipleIdenticalSubscriptions: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func test_userCreated_registeredTwice_bothReceiveAllEvents() async throws {
        async let events1 = collect(client.subscriptions.userCreated(), count: 2)
        async let events2 = collect(client.subscriptions.userCreated(), count: 2)

        let (e1, e2) = try await (events1, events2)

        XCTAssertEqual(e1.count, 2)
        XCTAssertEqual(e1[0].userCreated.id, "user-1")
        XCTAssertEqual(e1[1].userCreated.id, "user-2")
        XCTAssertEqual(e2.count, 2)
        XCTAssertEqual(e2[0].userCreated.id, "user-1")
        XCTAssertEqual(e2[1].userCreated.id, "user-2")
    }

    func test_userStatusChanged_sameArg_registeredTwice_bothReceiveEvent() async throws {
        async let events1 = collect(client.subscriptions.userStatusChanged(userId: "user-1"), count: 1)
        async let events2 = collect(client.subscriptions.userStatusChanged(userId: "user-1"), count: 1)

        let (e1, e2) = try await (events1, events2)

        XCTAssertEqual(e1[0].userStatusChanged.id, "user-1")
        XCTAssertEqual(e1[0].userStatusChanged.status, .active)
        XCTAssertEqual(e2[0].userStatusChanged.id, "user-1")
        XCTAssertEqual(e2[0].userStatusChanged.status, .active)
    }
}

// ── MultipleDifferentSubscriptions ────────────────────────────────────────────
// Different operations or same operation with different args — verifies that
// UUID routing delivers each event only to the correct collector.

final class SubscriptionsTest_MultipleDifferentSubscriptions: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func test_userCreated_and_userStatusChanged_runConcurrently() async throws {
        async let userCreatedEvents = collect(client.subscriptions.userCreated(), count: 1)
        async let statusEvents = collect(client.subscriptions.userStatusChanged(userId: "user-1"), count: 1)

        let (uc, sc) = try await (userCreatedEvents, statusEvents)

        XCTAssertEqual(uc[0].userCreated.id, "user-1")
        XCTAssertEqual(sc[0].userStatusChanged.id, "user-1")
        XCTAssertEqual(sc[0].userStatusChanged.status, .active)
    }

    func test_userStatusChanged_differentArgs_receiveIndependentEvents() async throws {
        async let events1 = collect(client.subscriptions.userStatusChanged(userId: "user-1"), count: 1)
        async let events2 = collect(client.subscriptions.userStatusChanged(userId: "user-2"), count: 1)

        let (e1, e2) = try await (events1, events2)

        XCTAssertEqual(e1[0].userStatusChanged.id, "user-1")
        XCTAssertEqual(e1[0].userStatusChanged.status, .active)
        XCTAssertEqual(e2[0].userStatusChanged.id, "user-2")
        XCTAssertEqual(e2[0].userStatusChanged.status, .inactive)
    }

    func test_userCreated_and_userCreateds_runConcurrently() async throws {
        async let singleEvents = collect(client.subscriptions.userCreated(), count: 1)
        async let listEvents = collect(client.subscriptions.userCreateds(ids: ["user-1", "user-2"]), count: 1)

        let (single, list) = try await (singleEvents, listEvents)

        XCTAssertEqual(single[0].userCreated.id, "user-1")
        XCTAssertNotNil(list[0].userCreateds)
        XCTAssertEqual(list[0].userCreateds!.count, 2)
        XCTAssertEqual(list[0].userCreateds![0].id, "user-1")
        XCTAssertEqual(list[0].userCreateds![1].id, "user-2")
    }
}

// ── userStatusChanged ──────────────────────────────────────────────────────────

final class SubscriptionsTest_UserStatusChanged: XCTestCase {
    var client: GraphLinkClient!

    override func setUp() {
        super.setUp()
        client = Fixtures.newRealClient()
    }

    func test_event_returnsCorrectUser() async throws {
        let events = try await collect(client.subscriptions.userStatusChanged(userId: "user-1"), count: 1)
        XCTAssertEqual(events[0].userStatusChanged.id, "user-1")
    }

    func test_event_status_isCorrect() async throws {
        let events = try await collect(client.subscriptions.userStatusChanged(userId: "user-1"), count: 1)
        XCTAssertEqual(events[0].userStatusChanged.status, .active)
    }
}
