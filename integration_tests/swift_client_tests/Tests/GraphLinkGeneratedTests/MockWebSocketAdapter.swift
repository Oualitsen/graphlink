import Foundation
@testable import GraphLinkGenerated

final class MockWebSocketAdapter: GraphLinkWebSocketAdapter, @unchecked Sendable {
    private var messageListener: (@Sendable (String) -> Void)?
    private var reconnectListener: (@Sendable () -> Void)?

    /// Raw JSON strings sent by the client to the server.
    private(set) var sentMessages: [String] = []

    /// Decoded versions of every sent message (for inspection in tests).
    var sentMessagesDecoded: [[String: Any?]] {
        sentMessages.map { (try? GraphLinkJson.decode($0.data(using: .utf8)!)) ?? [:] }
    }

    private(set) var connected = false

    // ── Protocol helpers ──────────────────────────────────────────────────────

    /// Simulate the server sending connection_ack.
    func deliverConnectionAck() {
        deliver(jsonString(["type": "connection_ack"]))
    }

    /// Simulate the server sending a next (data) message.
    func deliverNext(_ id: String, _ data: [String: Any?]) {
        deliver(jsonString(["type": "next", "id": id, "payload": ["data": data]]))
    }

    /// Simulate the server sending a complete message.
    func deliverComplete(_ id: String) {
        deliver(jsonString(["type": "complete", "id": id]))
    }

    /// Simulate the server sending an error message.
    func deliverError(_ id: String, _ errors: [[String: Any?]]) {
        deliver(jsonString(["type": "error", "id": id, "payload": errors]))
    }

    /// Deliver a raw JSON string directly to the registered message listener.
    func deliver(_ message: String) {
        guard let messageListener else {
            fatalError("MockWebSocketAdapter: no message listener registered")
        }
        messageListener(message)
    }

    /// Returns the subscription id from the last 'subscribe' message sent by the client.
    func getLastSubscriptionId() -> String {
        guard let msg = sentMessagesDecoded.last(where: { ($0["type"] as? String) == "subscribe" }) else {
            fatalError("No subscribe message found in sent messages")
        }
        guard let id = msg["id"] as? String else {
            fatalError("subscribe message has no 'id' field")
        }
        return id
    }

    func simulateReconnect() { reconnectListener?() }

    func reset() {
        sentMessages.removeAll()
        connected = false
        messageListener = nil
        reconnectListener = nil
    }

    // ── GraphLinkWebSocketAdapter ─────────────────────────────────────────────

    func connect(onConnect: @escaping @Sendable () -> Void, onFailure: @escaping @Sendable (Error) -> Void) {
        connected = true
        onConnect()
    }

    func sendMessage(_ message: String) {
        sentMessages.append(message)
    }

    func close() {
        connected = false
    }

    func setMessageListener(_ listener: @escaping @Sendable (String) -> Void) {
        messageListener = listener
    }

    func setReconnectListener(_ onReconnect: @escaping @Sendable () -> Void) {
        reconnectListener = onReconnect
    }
}
