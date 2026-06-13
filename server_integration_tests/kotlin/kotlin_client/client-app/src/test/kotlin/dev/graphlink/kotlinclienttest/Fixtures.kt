package dev.graphlink.kotlinclienttest

import dev.graphlink.kotlinclient.generated.client.DefaultGraphLinkClientAdapter
import dev.graphlink.kotlinclient.generated.client.DefaultGraphLinkWebSocketAdapter
import dev.graphlink.kotlinclient.generated.client.GraphLinkClient
import dev.graphlink.kotlinclient.generated.client.KotlinxSerializationGraphLinkJsonCodec

object Fixtures {

    val SERVER_PORT: Int = System.getProperty("serverPort")?.toIntOrNull() ?: 9994

    val HTTP_URL = "http://localhost:$SERVER_PORT/graphql"
    val WS_URL = "ws://localhost:$SERVER_PORT/graphql"

    fun newClient(): GraphLinkClient {
        val codec = KotlinxSerializationGraphLinkJsonCodec()
        return GraphLinkClient(
            adapter = DefaultGraphLinkClientAdapter(HTTP_URL),
            wsAdapter = DefaultGraphLinkWebSocketAdapter(WS_URL, protocols = listOf("graphql-transport-ws")),
            encoder = codec,
            decoder = codec,
        )
    }
}
