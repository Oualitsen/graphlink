package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkGetNotSupported
import dev.graphlink.test.generated.client.GraphLinkSha256
import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec
import dev.graphlink.test.generated.interfaces.GraphLinkClientAdapter

class ApqServer {
    private val codec = KotlinxSerializationGraphLinkJsonCodec()
    private val responses = mutableMapOf<String, Map<String, Any?>>()
    private val registered = mutableSetOf<String>()

    val requests = mutableListOf<Map<String, Any?>>()
    val methods = mutableListOf<String>()

    var supported = true
    var getSupported = true
    var notFoundMessage = "PersistedQueryNotFound"
    var failWith: Exception? = null
    var getFailWith: Exception? = null

    val post = GraphLinkClientAdapter { handle("POST", it, failWith) }

    val get = GraphLinkClientAdapter {
        if (!getSupported) {
            methods += "GET"
            throw GraphLinkGetNotSupported("GET is not allowed")
        }
        handle("GET", it, getFailWith)
    }

    fun respondTo(operationName: String, data: Map<String, Any?>) {
        responses[operationName] = mapOf("data" to data)
    }

    fun respondWithErrors(operationName: String, errors: List<Map<String, Any?>>) {
        responses[operationName] = mapOf("data" to null, "errors" to errors)
    }

    fun evict() = registered.clear()

    fun isHashOnly(body: Map<String, Any?>) = body.containsKey("extensions") && !body.containsKey("query")

    private fun handle(method: String, payload: String, failure: Exception?): String {
        methods += method
        val body = codec.decode(payload)
        requests += body
        if (failure != null) throw failure

        val persisted = (body["extensions"] as? Map<*, *>)?.get("persistedQuery") as? Map<*, *>
        if (persisted != null) {
            if (!supported) return error("PersistedQueryNotSupported", "PERSISTED_QUERY_NOT_SUPPORTED")
            val hash = persisted["sha256Hash"] as String
            val query = body["query"] as String?
            if (query == null) {
                if (hash !in registered) return error(notFoundMessage, "PERSISTED_QUERY_NOT_FOUND")
            } else {
                if (GraphLinkSha256.hex(query) != hash) return error("provided sha does not match query", "INTERNAL_SERVER_ERROR")
                registered += hash
            }
        }
        val operationName = body["operationName"] as String
        val response = responses[operationName] ?: error("No response registered for $operationName")
        return codec.encode(response)
    }

    private fun error(message: String, code: String): String =
        codec.encode(mapOf("errors" to listOf(mapOf("message" to message, "extensions" to mapOf("code" to code)))))
}
