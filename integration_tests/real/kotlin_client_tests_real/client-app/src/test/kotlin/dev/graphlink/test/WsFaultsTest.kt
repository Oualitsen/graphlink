package dev.graphlink.test

import dev.graphlink.test.generated.client.DefaultGraphLinkClientAdapter
import dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.client.GraphLinkException
import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.onCompletion
import kotlinx.serialization.json.*
import org.junit.jupiter.api.Timeout
import java.io.File
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.test.Test
import kotlin.test.assertTrue

@Timeout(value = 5, unit = TimeUnit.MINUTES)
class WsFaultsTest {

    private companion object {
        val FAULT_PORT = (System.getenv("WS_FAULT_PORT") ?: "9947").toInt()
        val FAULT_URL = "http://127.0.0.1:$FAULT_PORT"
        val HTTP: HttpClient = HttpClient.newHttpClient()

        val KNOWN_DEFECTS = mapOf<String, String>()

        fun send(method: String, path: String): String {
            val builder = HttpRequest.newBuilder(URI.create(FAULT_URL + path))
            val request = if (method == "POST") builder.POST(HttpRequest.BodyPublishers.noBody()) else builder.GET()
            return HTTP.send(request.build(), HttpResponse.BodyHandlers.ofString()).body()
        }
    }

    @Test
    fun websocketFaults() = runBlocking<Unit> {
        val cases = Json.parseToJsonElement(File("../../fault_server/ws_cases.json").readText()).jsonArray
        val failures = mutableListOf<String>()
        for (case in cases) {
            val fault = case.jsonObject["fault"]!!.jsonPrimitive.content
            if (fault in KNOWN_DEFECTS) {
                println("skipped $fault: ${KNOWN_DEFECTS[fault]}")
                continue
            }
            runCatching { run(case.jsonObject, fault) }.onFailure { failures += "$fault: ${it.message}" }
        }
        assertTrue(failures.isEmpty(), failures.joinToString("\n"))
    }

    private suspend fun run(case: JsonObject, fault: String) {
        send("POST", "/_reset")
        send("POST", "/_arm?fault=$fault&times=${case["times"]?.jsonPrimitive?.int ?: 1}")
        val codec = KotlinxSerializationGraphLinkJsonCodec()
        val ws = DefaultGraphLinkWebSocketAdapter("ws://127.0.0.1:$FAULT_PORT/graphql", null)
        val client = GraphLinkClient(DefaultGraphLinkClientAdapter("$FAULT_URL/graphql", codec), ws, MockMultipartAdapter(), codec, codec)
        val events = CopyOnWriteArrayList<Int>()
        val error = AtomicReference<Throwable?>()
        val settledFlag = AtomicBoolean()
        val job = CoroutineScope(Dispatchers.IO).launch {
            client.subscriptions.counterTick()
                .catch { error.set(it); settledFlag.set(true) }
                .onCompletion { settledFlag.set(true) }
                .collect { events.add(it.counterTick) }
        }
        try {
            val wait = case["waitSeconds"]?.jsonPrimitive?.int
            val deadline = System.currentTimeMillis() + (wait ?: 8) * 1000L
            while (!settledFlag.get() && System.currentTimeMillis() < deadline) delay(100)
            val log = Json.parseToJsonElement(send("GET", "/_ws_log")).jsonArray
            val sent = log.flatMap { connection -> connection.jsonObject["frames"]!!.jsonArray.map { it.jsonObject["type"]!!.jsonPrimitive.content } }

            if (wait == null) {
                check(settledFlag.get()) { "the subscription hung" }
                when (case["expect"]?.jsonPrimitive?.content) {
                    "value" -> {
                        check(error.get() == null) { "unexpected failure ${error.get()}" }
                        check(events.toList() == listOf(1)) { "want [1], got $events" }
                    }
                    "error" -> {
                        val failure = error.get()
                        check(failure != null) { "no failure, events=$events" }
                        val message = case["message"]?.jsonPrimitive?.content
                        if (message != null) {
                            val text = (failure as? GraphLinkException)?.errors?.joinToString { it.message } ?: failure.message.orEmpty()
                            check(text.contains(message)) { "failure does not mention $message: $text" }
                        }
                    }
                }
            }
            if (case["noSubscribeBeforeAck"]?.jsonPrimitive?.boolean == true) check("subscribe" !in sent) { "subscribe before the ack" }
            if (case["pong"]?.jsonPrimitive?.boolean == true) check("pong" in sent) { "ping not answered" }
            case["maxConnections"]?.jsonPrimitive?.int?.let { check(log.size <= it) { "${log.size} connections" } }
            case["minConnections"]?.jsonPrimitive?.int?.let { check(log.size >= it) { "${log.size} connections" } }
        } finally {
            job.cancel()
            ws.close()
        }
    }
}
