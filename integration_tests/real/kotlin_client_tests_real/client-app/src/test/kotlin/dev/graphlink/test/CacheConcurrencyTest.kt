package dev.graphlink.test

import dev.graphlink.test.Fixtures.newRealClient
import kotlinx.coroutines.*
import kotlin.test.*

class CacheConcurrencyTest {

    private val client = newRealClient()
    private fun freshId() = "kotlin-${System.nanoTime()}"

    @Test
    fun concurrentRequestsForTwoDifferentKeysMakeTwoCalls() = runBlocking<Unit> {
        val id = freshId()
        listOf("$id-a", "$id-b").map { key -> async(Dispatchers.IO) { client.queries.cachedSlow(key, 300) } }.awaitAll()
        assertEquals(1, client.queries.cachedSlowCalls("$id-a").cachedSlowCalls)
        assertEquals(1, client.queries.cachedSlowCalls("$id-b").cachedSlowCalls)
    }

    @Test
    fun aResponseInFlightDuringAnInvalidationIsNotStored() = runBlocking<Unit> {
        val id = freshId()
        val slow = async(Dispatchers.IO) { client.queries.cachedSlow(id, 600).cachedSlow }
        delay(150)
        client.mutations.bumpSlow(id)
        assertEquals(0, slow.await())
        assertEquals(1, client.queries.cachedSlow(id, 600).cachedSlow)
    }
}
