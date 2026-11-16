package dev.graphlink.test

import dev.graphlink.test.Fixtures.newRealClient
import dev.graphlink.test.generated.client.GraphLinkClient
import kotlinx.coroutines.test.runTest
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.*

// The server fails the first cachedFlaky / cachedFlakyNullable call per id and counts every call.
class CacheErrorsTest {

    private companion object {
        val next = AtomicInteger()
    }

    private lateinit var client: GraphLinkClient
    private lateinit var id: String

    @BeforeTest
    fun setUp() {
        client = newRealClient()
        id = "kotlin-${System.nanoTime()}-${next.incrementAndGet()}"
    }

    private suspend fun serverCalls() = client.queries.cachedFlakyCalls(id).cachedFlakyCalls

    @Test
    fun aFailedResponseIsNotCached() = runTest {
        assertFailsWith<Exception> { client.queries.cachedFlaky(id) }
        assertEquals(1, serverCalls())

        assertEquals("user-1", client.queries.cachedFlaky(id).cachedFlaky.id)
        assertEquals(2, serverCalls())

        assertEquals("user-1", client.queries.cachedFlaky(id).cachedFlaky.id)
        assertEquals(2, serverCalls())
    }

    @Test
    fun aPartialFailureIsNotCached() = runTest {
        assertFailsWith<Exception> { client.queries.cachedFlakyNullable(id) }
        assertEquals(1, serverCalls())

        assertEquals("user-1", client.queries.cachedFlakyNullable(id).cachedFlakyNullable?.id)
        assertEquals(2, serverCalls())

        assertEquals("user-1", client.queries.cachedFlakyNullable(id).cachedFlakyNullable?.id)
        assertEquals(2, serverCalls())
    }
}
