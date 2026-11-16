package dev.graphlink.test

import dev.graphlink.test.Fixtures.SERVER_URL
import dev.graphlink.test.Fixtures.WS_URL
import dev.graphlink.test.generated.client.DefaultGraphLinkClientAdapter
import dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.client.GraphLinkException
import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlin.test.*

class AuthTest {

    private companion object {
        val next = AtomicInteger()
    }

    private val adapters = mutableListOf<DefaultGraphLinkWebSocketAdapter>()

    @AfterTest
    fun tearDown() = adapters.forEach { it.close() }

    private fun clientWith(headers: (() -> Map<String, String>)?): GraphLinkClient {
        val codec = KotlinxSerializationGraphLinkJsonCodec()
        val ws = DefaultGraphLinkWebSocketAdapter(WS_URL, headers)
        adapters.add(ws)
        return GraphLinkClient(DefaultGraphLinkClientAdapter(SERVER_URL, codec, headers), ws, MockMultipartAdapter(), codec, codec)
    }

    @Test
    fun headersProviderValuesReachTheServer() = runTest {
        val client = clientWith { mapOf("X-Test" to "v1") }
        assertEquals("v1", client.queries.echoHeader("X-Test").echoHeader)
        assertNull(client.queries.echoHeader("X-Other").echoHeader)
    }

    @Test
    fun headersProviderIsEvaluatedOnEveryRequest() = runTest {
        val token = AtomicReference("first")
        val client = clientWith { mapOf("Authorization" to "Bearer ${token.get()}") }
        assertEquals("first", client.queries.whoAmI().whoAmI)
        token.set("second")
        assertEquals("second", client.queries.whoAmI().whoAmI)
    }

    @Test
    fun aMissingTokenIsAGraphLinkException() = runTest {
        val e = assertFailsWith<GraphLinkException> { clientWith(null).queries.whoAmI() }
        assertTrue(e.errors.isNotEmpty())
    }

    @Test
    fun connectionInitCarriesTheToken() = runTest {
        val token = "kotlin-${System.nanoTime()}-${next.incrementAndGet()}"
        var error: Throwable? = null
        val ticks = clientWith { mapOf("Authorization" to "Bearer $token") }.subscriptions
            .secureTicks(3).catch { error = it }.toList()
        assertNull(error)
        assertEquals(listOf(1, 2, 3), ticks.map { it.secureTicks })
        assertEquals(1, clientWith(null).queries.secureTickStarts(token).secureTickStarts)
    }

    @Test
    fun aSubscriptionWithoutATokenFails() = runTest {
        var error: Throwable? = null
        val ticks = clientWith(null).subscriptions.secureTicks(3).catch { error = it }.toList()
        assertTrue(ticks.isEmpty())
        assertNotNull(error)
    }
}
