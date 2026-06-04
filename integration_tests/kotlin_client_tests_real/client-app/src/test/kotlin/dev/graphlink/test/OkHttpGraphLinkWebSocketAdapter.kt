package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkWebSocketAdapter
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

class OkHttpGraphLinkWebSocketAdapter(private val url: String) : GraphLinkWebSocketAdapter {

    private val client = OkHttpClient()
    private var ws: WebSocket? = null
    private var messageListener: ((String) -> Unit)? = null
    private var reconnectListener: (() -> Unit)? = null

    override fun connect(onConnect: () -> Unit, onFailure: (Throwable) -> Unit) {
        val request = Request.Builder()
            .url(url)
            .header("Sec-WebSocket-Protocol", "graphql-transport-ws")
            .build()
        ws = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) = onConnect()
            override fun onMessage(webSocket: WebSocket, text: String) { messageListener?.invoke(text) }
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) = onFailure(t)
        })
    }

    override fun sendMessage(message: String) { ws?.send(message) }

    override fun close() { ws?.close(1000, null) }

    override fun setMessageListener(listener: (String) -> Unit) { messageListener = listener }

    override fun setReconnectListener(onReconnect: () -> Unit) { reconnectListener = onReconnect }
}
