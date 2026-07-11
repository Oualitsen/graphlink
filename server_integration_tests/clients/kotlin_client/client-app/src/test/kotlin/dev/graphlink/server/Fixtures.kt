package dev.graphlink.server

import dev.graphlink.server.generated.client.DefaultGraphLinkClientAdapter
import dev.graphlink.server.generated.client.DefaultGraphLinkWebSocketAdapter
import dev.graphlink.server.generated.client.GraphLinkClient
import dev.graphlink.server.generated.client.KotlinxSerializationGraphLinkJsonCodec

object Fixtures {

    private val port: Int
        get() = System.getenv("SERVER_PORT")?.toIntOrNull() ?: 9997

    val SERVER_URL: String get() = "http://localhost:$port/graphql"
    val WS_URL: String get() = "ws://localhost:$port/graphql"

    fun newClient(): GraphLinkClient {
        val codec = KotlinxSerializationGraphLinkJsonCodec()
        return GraphLinkClient(
            DefaultGraphLinkClientAdapter(SERVER_URL),
            DefaultGraphLinkWebSocketAdapter(WS_URL),
            codec, codec,
        )
    }
}
