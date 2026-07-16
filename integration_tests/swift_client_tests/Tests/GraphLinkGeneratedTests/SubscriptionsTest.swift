import XCTest
@testable import GraphLinkGenerated

/// `GraphLinkSubscriptions.*()` methods start the connect/subscribe handshake
/// synchronously (the `AsyncThrowingStream` build closure runs eagerly on
/// creation, and `MockWebSocketAdapter.connect` invokes `onConnect` inline),
/// so by the time the stream value is returned `connection_init` has already
/// been sent. That lets tests drive the mock handshake — deliver the ack,
/// grab the subscription id, deliver `next` messages — *before* starting to
/// iterate the stream; `AsyncThrowingStream` buffers unconsumed yields.

// ── userCreated ──────────────────────────────────────────────────────────────

final class SubscriptionsTest_UserCreated: XCTestCase {
    var adapter: MockAdapter!
    var wsAdapter: MockWebSocketAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        wsAdapter = MockWebSocketAdapter()
        client = Fixtures.newClient(adapter, wsAdapter)
    }

    func test_singleEvent_deserializedCorrectly() async throws {
        let stream = client.subscriptions.userCreated()
        wsAdapter.deliverConnectionAck()
        let subId = wsAdapter.getLastSubscriptionId()
        wsAdapter.deliverNext(subId, n(("userCreated", Fixtures.kUserAliceJson)))

        var events: [UserCreatedResponse] = []
        for try await value in stream {
            events.append(value)
            break
        }

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].userCreated.id, "user-1")
    }

    func test_singleEvent_name_isCorrect() async throws {
        let stream = client.subscriptions.userCreated()
        wsAdapter.deliverConnectionAck()
        let subId = wsAdapter.getLastSubscriptionId()
        wsAdapter.deliverNext(subId, n(("userCreated", Fixtures.kUserAliceJson)))

        var events: [UserCreatedResponse] = []
        for try await value in stream {
            events.append(value)
            break
        }

        XCTAssertEqual(events[0].userCreated.name, "Alice Smith")
    }

    func test_singleEvent_status_deserializesToEnum() async throws {
        let stream = client.subscriptions.userCreated()
        wsAdapter.deliverConnectionAck()
        let subId = wsAdapter.getLastSubscriptionId()
        wsAdapter.deliverNext(subId, n(("userCreated", Fixtures.kUserAliceJson)))

        var events: [UserCreatedResponse] = []
        for try await value in stream {
            events.append(value)
            break
        }

        XCTAssertEqual(events[0].userCreated.status, .active)
    }

    func test_multipleEvents_deliveredInOrder() async throws {
        let stream = client.subscriptions.userCreated()
        wsAdapter.deliverConnectionAck()
        let subId = wsAdapter.getLastSubscriptionId()
        wsAdapter.deliverNext(subId, n(("userCreated", Fixtures.kUserAliceJson)))
        wsAdapter.deliverNext(subId, n(("userCreated", Fixtures.kUserBobJson)))

        var events: [UserCreatedResponse] = []
        for try await value in stream {
            events.append(value)
            if events.count >= 2 { break }
        }

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].userCreated.id, "user-1")
        XCTAssertEqual(events[1].userCreated.id, "user-2")
    }

    func test_connectionInit_isSent_firstMessage() async throws {
        _ = client.subscriptions.userCreated()

        let first = wsAdapter.sentMessagesDecoded.first
        XCTAssertNotNil(first)
        XCTAssertEqual(first?["type"] as? String, "connection_init")
    }

    func test_subscribeMessage_isSent_afterConnectionAck() async throws {
        _ = client.subscriptions.userCreated()
        wsAdapter.deliverConnectionAck()

        let subscribeCount = wsAdapter.sentMessagesDecoded.filter { ($0["type"] as? String) == "subscribe" }.count
        XCTAssertEqual(subscribeCount, 1)
    }
}

// ── userStatusChanged ────────────────────────────────────────────────────────

final class SubscriptionsTest_UserStatusChanged: XCTestCase {
    var adapter: MockAdapter!
    var wsAdapter: MockWebSocketAdapter!
    var client: GraphLinkClient!

    override func setUp() {
        adapter = MockAdapter()
        wsAdapter = MockWebSocketAdapter()
        client = Fixtures.newClient(adapter, wsAdapter)
    }

    func test_event_deserializedCorrectly() async throws {
        let stream = client.subscriptions.userStatusChanged(userId: "user-1")
        wsAdapter.deliverConnectionAck()
        let subId = wsAdapter.getLastSubscriptionId()
        wsAdapter.deliverNext(subId, n(("userStatusChanged", Fixtures.kUserAliceJson)))

        var events: [UserStatusChangedResponse] = []
        for try await value in stream {
            events.append(value)
            break
        }

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].userStatusChanged.id, "user-1")
    }

    func test_event_status_isCorrect() async throws {
        let stream = client.subscriptions.userStatusChanged(userId: "user-1")
        wsAdapter.deliverConnectionAck()
        let subId = wsAdapter.getLastSubscriptionId()
        wsAdapter.deliverNext(subId, n(("userStatusChanged", Fixtures.kUserAliceJson)))

        var events: [UserStatusChangedResponse] = []
        for try await value in stream {
            events.append(value)
            break
        }

        XCTAssertEqual(events[0].userStatusChanged.status, .active)
    }

    func test_userId_sentInSubscribePayload() async throws {
        _ = client.subscriptions.userStatusChanged(userId: "user-42")
        wsAdapter.deliverConnectionAck()

        let subscribeMsg = wsAdapter.sentMessagesDecoded.first { ($0["type"] as? String) == "subscribe" }!
        let payload = subscribeMsg["payload"] as! [String: Any?]
        let variables = payload["variables"] as! [String: Any?]
        XCTAssertEqual(variables["userId"] as? String, "user-42")
    }
}
