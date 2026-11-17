package dev.graphlink.test

import dev.graphlink.test.SubscriptionReconnectTest.Companion.httpUrl
import dev.graphlink.test.SubscriptionReconnectTest.Companion.killPort
import dev.graphlink.test.SubscriptionReconnectTest.Companion.startServer
import dev.graphlink.test.SubscriptionReconnectTest.Companion.wsUrl
import dev.graphlink.test.generated.client.DefaultGraphLinkClientAdapter
import dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.onCompletion
import org.junit.jupiter.api.Timeout
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

@Timeout(value = 3, unit = TimeUnit.MINUTES)
class SubscriptionReconnectCasesTest {

    private companion object {
        const val PORT = 9935
    }

    private inner class Stream(label: String, count: Int, scope: CoroutineScope) {
        val events = CopyOnWriteArrayList<String>()
        val error = AtomicReference<Throwable?>()
        @Volatile var completed = false
        val job: Job = scope.launch {
            client.subscriptions.labelTicks(label, count)
                .catch { error.set(it) }
                .onCompletion { if (it == null && error.get() == null) completed = true }
                .collect { events.add(it.labelTicks) }
        }

        suspend fun awaitEvent(label: String) {
            val seen = events.size
            until("an event for $label after the restart") { events.drop(seen).any { it.startsWith("$label-") } }
        }
    }

    private var ws: DefaultGraphLinkWebSocketAdapter? = null
    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        killPort(PORT)
        startServer(PORT)
    }

    @AfterTest
    fun tearDown() {
        ws?.close()
        killPort(PORT)
    }

    private suspend fun until(what: String, check: () -> Boolean) {
        withTimeout(60_000) {
            while (!check()) delay(200)
        }.also { }
    }

    private fun connect(headers: (() -> Map<String, String>)? = null, maxAttempts: Int? = 10, maxDelayMs: Long = 30_000) {
        val codec = KotlinxSerializationGraphLinkJsonCodec()
        val adapter = DefaultGraphLinkWebSocketAdapter(wsUrl(PORT), headers, maxReconnectAttempts = maxAttempts, maxReconnectDelayMs = maxDelayMs)
        ws = adapter
        client = GraphLinkClient(DefaultGraphLinkClientAdapter(httpUrl(PORT), codec), adapter, MockMultipartAdapter(), codec, codec)
    }

    private suspend fun starts(label: String) = client.queries.labelTickStarts(label).labelTickStarts

    private suspend fun restart() = withContext(Dispatchers.IO) {
        killPort(PORT)
        startServer(PORT)
    }

    @Test
    fun resubscribesWithTheSameVariables() = runBlocking<Unit> {
        connect()
        val bob = Stream("bob", 1000, this)
        until("first event") { bob.events.isNotEmpty() }
        assertEquals("bob-1", bob.events.first())

        restart()
        bob.awaitEvent("bob")
        assertEquals(1, starts("bob"))
        bob.job.cancel()
    }

    @Test
    fun doesNotResubscribeACompletedSubscription() = runBlocking<Unit> {
        connect()
        val done = Stream("done", 2, this)
        until("completion") { done.completed }
        assertEquals(2, done.events.size)

        restart()
        delay(6000)
        assertEquals(0, starts("done"))
        assertEquals(2, done.events.size)
    }

    @Test
    fun doesNotReviveACancelledSubscription() = runBlocking<Unit> {
        connect()
        val cancelled = Stream("cancelled", 1000, this)
        until("first event") { cancelled.events.isNotEmpty() }
        cancelled.job.cancelAndJoin()
        delay(1000)

        restart()
        delay(6000)
        assertEquals(0, starts("cancelled"))
    }

    @Test
    fun resumesEveryOpenSubscriptionOnOneSocket() = runBlocking<Unit> {
        connect()
        val a = Stream("a", 1000, this)
        val b = Stream("b", 1000, this)
        until("first events") { a.events.isNotEmpty() && b.events.isNotEmpty() }

        restart()
        a.awaitEvent("a")
        b.awaitEvent("b")
        assertEquals(1, starts("a"))
        assertEquals(1, starts("b"))
        a.job.cancel()
        b.job.cancel()
    }

    @Test
    fun aRestartDuringConnectionInitSubscribesOnce() = runBlocking<Unit> {
        connect(headers = { mapOf("Ack-Delay" to "3000") })
        val init = Stream("init", 1000, this)
        delay(1000)

        restart()
        init.awaitEvent("init")
        delay(2000)
        assertEquals(1, starts("init"))
        init.job.cancel()
    }

    @Test
    fun givesUpWithAVisibleError() = runBlocking<Unit> {
        connect(maxAttempts = 2, maxDelayMs = 1000)
        val giveUp = Stream("giveup", 1000, this)
        until("first event") { giveUp.events.isNotEmpty() }
        killPort(PORT)

        until("an error or an end after the reconnect attempts ran out") { giveUp.error.get() != null || giveUp.completed }
        assertNotNull(giveUp.error.get())
    }
}
