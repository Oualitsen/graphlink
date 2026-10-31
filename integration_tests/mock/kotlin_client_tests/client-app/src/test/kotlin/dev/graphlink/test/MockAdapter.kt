package dev.graphlink.test

import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec
import dev.graphlink.test.generated.interfaces.GraphLinkClientAdapter

class MockAdapter : GraphLinkClientAdapter {

    var simulateFailure = false

    private val codec = KotlinxSerializationGraphLinkJsonCodec()
    private val responses = mutableMapOf<String, String>()
    private val _calls = mutableListOf<GraphLinkCall>()

    val calls: List<GraphLinkCall> get() = _calls
    fun getLastCall(): GraphLinkCall? = _calls.lastOrNull()
    fun getCallCount(): Int = _calls.size

    fun register(operationName: String, jsonResponse: String) {
        responses[operationName] = jsonResponse
    }

    fun registerData(operationName: String, data: Map<String, Any?>) {
        register(operationName, codec.encode(mapOf("data" to data)))
    }

    fun registerDataAndErrors(
        operationName: String,
        data: Map<String, Any?>,
        errors: List<Map<String, Any?>>,
    ) {
        register(operationName, codec.encode(mapOf("data" to data, "errors" to errors)))
    }

    fun registerErrors(operationName: String, errors: List<Map<String, Any?>>) {
        register(operationName, codec.encode(mapOf("data" to null, "errors" to errors)))
    }

    fun reset() {
        _calls.clear()
        responses.clear()
        simulateFailure = false
    }

    override suspend fun execute(payload: String): String {
        if (simulateFailure) error("Simulated network failure")

        val decoded = codec.decode(payload)
        val op = decoded["operationName"] as? String
        @Suppress("UNCHECKED_CAST")
        val variables = (decoded["variables"] as? Map<String, Any?>) ?: emptyMap()
        _calls += GraphLinkCall(op, variables, payload)

        return responses[op] ?: error(
            "MockAdapter: no response registered for \"$op\".\n" +
            "Registered operations: ${responses.keys}\n" +
            "Payload: $payload"
        )
    }
}
