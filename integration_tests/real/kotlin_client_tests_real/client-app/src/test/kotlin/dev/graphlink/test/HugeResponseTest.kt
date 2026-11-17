package dev.graphlink.test

import dev.graphlink.test.generated.client.DefaultGraphLinkClientAdapter
import dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Timeout
import java.io.File
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

@Timeout(value = 2, unit = TimeUnit.MINUTES)
class HugeResponseTest {

    private companion object {
        val FAULT_PORT = (System.getenv("WS_FAULT_PORT") ?: "9947").toInt()
        val FAULT_URL = "http://127.0.0.1:$FAULT_PORT"
        val HTTP: HttpClient = HttpClient.newHttpClient()

        fun post(path: String) {
            val request = HttpRequest.newBuilder(URI.create(FAULT_URL + path)).POST(HttpRequest.BodyPublishers.noBody()).build()
            HTTP.send(request, HttpResponse.BodyHandlers.discarding())
        }
    }

    @Test
    fun aTenMegabyteResponseIsDecodedWithoutLoss() = runBlocking<Unit> {
        val users = Json.parseToJsonElement(File("../../fault_server/huge_case.json").readText()).jsonObject["users"]!!.jsonPrimitive.int
        post("/_reset")
        post("/_arm?fault=huge-users")
        val codec = KotlinxSerializationGraphLinkJsonCodec()
        val ws = DefaultGraphLinkWebSocketAdapter("ws://127.0.0.1:$FAULT_PORT/graphql", null)
        val client = GraphLinkClient(DefaultGraphLinkClientAdapter("$FAULT_URL/graphql", codec), ws, MockMultipartAdapter(), codec, codec)
        try {
            val started = System.nanoTime()
            val response = client.queries.fetchBigUsers(count = users)
            val elapsedMs = (System.nanoTime() - started) / 1_000_000

            val list = response.bigUsers
            assertEquals(users, list.size)
            assertEquals("user-0", list.first().id)
            assertEquals("User ${users - 1} Ünï 日本", list.last().name)
            assertEquals("user-${users - 1}@example.com", list.last().email)
            assertEquals("INACTIVE", list[1].status.name)
            assertEquals(listOf("alpha", "beta"), list[users / 2].tags)
            assertNull(list.first().address.zip)
            assertTrue(elapsedMs < 30_000, "decoding took $elapsedMs ms")

            post("/_arm?fault=huge-users")
            assertEquals(users, client.queries.fetchBigUsers(count = users).bigUsers.size)
        } finally {
            ws.close()
        }
    }
}
