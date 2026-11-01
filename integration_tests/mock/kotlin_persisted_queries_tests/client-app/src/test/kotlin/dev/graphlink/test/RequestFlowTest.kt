package dev.graphlink.test

import dev.graphlink.test.Fixtures.kPostJson
import dev.graphlink.test.Fixtures.kUserAliceJson
import dev.graphlink.test.Helpers.createUserInput
import dev.graphlink.test.Helpers.hashOf
import dev.graphlink.test.generated.client.GraphLinkSha256
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*

class RequestFlowTest {
    private lateinit var server: ApqServer
    private lateinit var client: dev.graphlink.test.generated.client.GraphLinkClient

    @BeforeTest
    fun setUp() {
        server = ApqServer()
        client = Helpers.newClient(server)
    }

    @Nested
    inner class LongQuery {
        @BeforeTest
        fun register() = server.respondTo("persistedLongQuery", mapOf("getUser" to kUserAliceJson))

        @Test
        fun `is sent as a hash first and registered by the retry`() = runTest {
            val res = client.queries.persistedLongQuery("user-1")

            assertEquals("Alice Smith", res.getUser.name)
            assertEquals(2, server.requests.size)
            assertFalse(server.requests[0].containsKey("query"))
            assertEquals("persistedLongQuery", server.requests[0]["operationName"])
            assertEquals(mapOf("id" to "user-1"), server.requests[0]["variables"])
            assertTrue(server.requests[1]["query"] is String)
            assertEquals(mapOf("id" to "user-1"), server.requests[1]["variables"])
        }

        @Test
        fun `the hash is the SHA-256 of the query that the retry carries`() = runTest {
            client.queries.persistedLongQuery("user-1")

            val retry = server.requests[1]
            assertEquals(mapOf("version" to 1L, "sha256Hash" to GraphLinkSha256.hex(retry["query"] as String)), hashOf(retry))
            assertEquals(hashOf(retry), hashOf(server.requests[0]))
        }

        @Test
        fun `is a single request once the server knows it`() = runTest {
            client.queries.persistedLongQuery("user-1")
            server.requests.clear()

            client.queries.persistedLongQuery("user-2")

            assertEquals(1, server.requests.size)
            assertTrue(server.isHashOnly(server.requests.single()))
            assertEquals(mapOf("id" to "user-2"), server.requests.single()["variables"])
        }

        @Test
        fun `is registered again after the server evicts it`() = runTest {
            client.queries.persistedLongQuery("user-1")
            server.evict()
            server.requests.clear()

            val res = client.queries.persistedLongQuery("user-1")

            assertEquals("Alice Smith", res.getUser.name)
            assertEquals(2, server.requests.size)
            assertTrue(server.isHashOnly(server.requests[0]))
            assertTrue(server.requests[1].containsKey("query"))
        }
    }

    @Test
    fun `a short query is sent in full, with no hash`() = runTest {
        server.respondTo("persistedShortQuery", mapOf("listUsers" to emptyList<Any>()))

        client.queries.persistedShortQuery()

        assertEquals(1, server.requests.size)
        assertTrue((server.requests.single()["query"] as String).contains("listUsers"))
        assertFalse(server.requests.single().containsKey("extensions"))
    }

    @Test
    fun `a long mutation uses the same hash-then-register flow`() = runTest {
        server.respondTo("persistedLongMutation", mapOf("createUser" to kUserAliceJson))

        val res = client.mutations.persistedLongMutation(createUserInput)

        assertEquals("Alice Smith", res.createUser.name)
        assertEquals(2, server.requests.size)
        assertTrue(server.isHashOnly(server.requests[0]))
        assertTrue(server.requests[1].containsKey("query"))
    }

    @Nested
    inner class ServerWithoutApq {
        @BeforeTest
        fun register() {
            server.supported = false
            server.respondTo("persistedLongQuery", mapOf("getUser" to kUserAliceJson))
        }

        @Test
        fun `gets the full query right after the first refusal`() = runTest {
            val res = client.queries.persistedLongQuery("user-1")

            assertEquals("Alice Smith", res.getUser.name)
            assertEquals(2, server.requests.size)
            assertTrue(server.requests[1].containsKey("query"))
            assertFalse(server.requests[1].containsKey("extensions"))
        }

        @Test
        fun `is not asked about hashes again`() = runTest {
            client.queries.persistedLongQuery("user-1")
            server.requests.clear()

            client.queries.persistedLongQuery("user-2")

            assertEquals(1, server.requests.size)
            assertTrue(server.requests.single().containsKey("query"))
            assertFalse(server.requests.single().containsKey("extensions"))
        }
    }

    @Test
    fun `a server that reports a missing hash only by its code still gets the retry`() = runTest {
        server.notFoundMessage = "Unknown query"
        server.respondTo("persistedLongQuery", mapOf("getUser" to kUserAliceJson))

        val res = client.queries.persistedLongQuery("user-1")

        assertEquals("Alice Smith", res.getUser.name)
        assertEquals(2, server.requests.size)
        assertTrue(server.requests[1].containsKey("query"))
    }

    @Test
    fun `a GraphQL error is returned as is, without a second request`() = runTest {
        server.respondTo("persistedLongQuery", mapOf("getUser" to kUserAliceJson))
        client.queries.persistedLongQuery("user-1")
        server.requests.clear()
        server.respondWithErrors("persistedLongQuery", listOf(mapOf("message" to "boom")))

        assertFails { client.queries.persistedLongQuery("user-1") }
        assertEquals(1, server.requests.size)
    }

    @Test
    fun `a transport failure propagates, without a second request`() = runTest {
        server.respondTo("persistedLongMutation", mapOf("createUser" to kUserAliceJson))
        server.failWith = IllegalStateException("timeout")

        val e = assertFailsWith<IllegalStateException> { client.mutations.persistedLongMutation(createUserInput) }
        assertEquals("timeout", e.message)
        assertEquals(listOf("POST"), server.methods)
    }

    @Test
    fun `a cached query hashes the assembled request, not its pieces`() = runTest {
        server.respondTo("fetchCachedPair", mapOf("user" to kUserAliceJson, "post" to kPostJson))

        val res = client.queries.fetchCachedPair("user-1", "post-1")

        assertEquals("Alice Smith", res.user.name)
        assertEquals(2, server.requests.size)
        val retry = server.requests[1]
        assertEquals(GraphLinkSha256.hex(retry["query"] as String), hashOf(retry)["sha256Hash"])
        assertTrue((retry["query"] as String).contains("getCachedUser"))
    }
}
