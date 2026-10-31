package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkWebSocketAdapter
import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec

class MockWebSocketAdapter : GraphLinkWebSocketAdapter {

    private val codec = KotlinxSerializationGraphLinkJsonCodec()
    private var messageListener: ((String) -> Unit)? = null
    private var reconnectListener: (() -> Unit)? = null

    /** Raw JSON strings sent by the client to the server. */
    val sentMessages = mutableListOf<String>()

    /** Decoded versions of every sent message (for inspection in tests). */
    val sentMessagesDecoded: List<Map<String, Any?>>
        get() = sentMessages.map { codec.decode(it) }

    var connected = false

    // ── Protocol helpers ──────────────────────────────────────────────────────

    /** Simulate the server sending connection_ack. */
    fun deliverConnectionAck() {
        deliver(codec.encode(mapOf("type" to "connection_ack")))
    }

    /** Simulate the server sending a next (data) message. */
    fun deliverNext(id: String, data: Map<String, Any?>) {
        deliver(codec.encode(mapOf(
            "type" to "next",
            "id"   to id,
            "payload" to mapOf("data" to data),
        )))
    }

    /** Simulate the server sending a complete message. */
    fun deliverComplete(id: String) {
        deliver(codec.encode(mapOf("type" to "complete", "id" to id)))
    }

    /** Simulate the server sending an error message. */
    fun deliverError(id: String, errors: List<Map<String, Any?>>) {
        deliver(codec.encode(mapOf("type" to "error", "id" to id, "payload" to errors)))
    }

    /** Deliver a raw JSON string directly to the registered message listener. */
    fun deliver(message: String) {
        messageListener?.invoke(message)
            ?: error("MockWebSocketAdapter: no message listener registered")
    }

    /** Returns the subscription id from the last 'subscribe' message sent by the client. */
    fun getLastSubscriptionId(): String {
        val msg = sentMessagesDecoded.lastOrNull { it["type"] == "subscribe" }
            ?: error("No subscribe message found in sent messages")
        return msg["id"] as? String
            ?: error("subscribe message has no 'id' field")
    }

    fun simulateReconnect() = reconnectListener?.invoke()

    fun reset() {
        sentMessages.clear()
        connected = false
        messageListener = null
        reconnectListener = null
    }

    // ── GraphLinkWebSocketAdapter ─────────────────────────────────────────────

    override fun connect(onConnect: () -> Unit, onFailure: (Throwable) -> Unit) {
        connected = true
        onConnect()
    }

    override fun sendMessage(message: String) {
        sentMessages += message
    }

    override fun close() {
        connected = false
    }

    override fun setMessageListener(listener: (String) -> Unit) {
        messageListener = listener
    }

    override fun setReconnectListener(onReconnect: () -> Unit) {
        reconnectListener = onReconnect
    }
}
