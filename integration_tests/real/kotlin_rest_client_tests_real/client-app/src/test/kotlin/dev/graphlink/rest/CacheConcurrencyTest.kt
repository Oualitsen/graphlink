package dev.graphlink.rest

import dev.graphlink.rest.generated.client.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.assertEquals

class CacheConcurrencyTest {
    private lateinit var client: GraphLinkClient
    private lateinit var name: String

    private companion object {
        val sequence = AtomicInteger()
    }

    @BeforeEach
    fun setUp() {
        resetServer()
        client = newClient(store = InMemoryGraphLinkCacheStore())
        name = "kt-${System.nanoTime()}-${sequence.incrementAndGet()}"
    }

    @Test
    fun concurrentRequestsForTwoDifferentKeysMakeTwoCalls() = runBlocking {
        listOf("$name-a", "$name-b").map { async(Dispatchers.IO) { client.queries.counterSlow(name = it, delayMs = 300) } }.awaitAll()
        assertEquals(1, client.queries.counterCalls(name = "$name-a").n)
        assertEquals(1, client.queries.counterCalls(name = "$name-b").n)
    }

    @Test
    fun concurrentRequestsForTheSameKeyShareOneCall() = runBlocking {
        val results = (1..3).map { async(Dispatchers.IO) { client.queries.counterSlow(name = name, delayMs = 300).n } }.awaitAll()
        assertEquals(listOf(1, 1, 1), results)
        assertEquals(1, client.queries.counterCalls(name = name).n)
    }

    @Test
    fun aResponseInFlightDuringAnInvalidationIsNotStored() = runBlocking {
        val slow = async(Dispatchers.IO) { client.queries.counterSlow(name = name, delayMs = 600).n }
        delay(150)
        client.mutations.touchSlow(name = name)
        assertEquals(1, slow.await())
        assertEquals(2, client.queries.counterSlow(name = name, delayMs = 600).n)
    }
}
