package dev.graphlink.test

import dev.graphlink.test.Fixtures.kUserAliceJson
import dev.graphlink.test.Helpers.createUserInput
import kotlinx.coroutines.test.runTest
import kotlin.test.*

class GetAdapterTest {
    private lateinit var server: ApqServer
    private lateinit var client: dev.graphlink.test.generated.client.GraphLinkClient

    @BeforeTest
    fun setUp() {
        server = ApqServer()
        client = Helpers.newClient(server)
        server.respondTo("persistedLongQuery", mapOf("getUser" to kUserAliceJson))
        server.respondTo("persistedShortQuery", mapOf("listUsers" to emptyList<Any>()))
        server.respondTo("persistedLongMutation", mapOf("createUser" to kUserAliceJson))
    }

    @Test
    fun `a long query asks with a GET first and registers with a POST`() = runTest {
        client.queries.persistedLongQuery("user-1")

        assertEquals(listOf("GET", "POST"), server.methods)
        assertTrue(server.isHashOnly(server.requests[0]))
        assertTrue(server.requests[1].containsKey("query"))
    }

    @Test
    fun `a long query is a single GET once the server knows it`() = runTest {
        client.queries.persistedLongQuery("user-1")
        server.methods.clear()

        client.queries.persistedLongQuery("user-2")

        assertEquals(listOf("GET"), server.methods)
    }

    @Test
    fun `the GET adapter gets the hash-only payload, with no query`() = runTest {
        client.queries.persistedLongQuery("user-1")

        assertEquals(setOf("extensions", "operationName", "variables"), server.requests.first().keys)
    }

    @Test
    fun `a short query is a plain POST`() = runTest {
        client.queries.persistedShortQuery()

        assertEquals(listOf("POST"), server.methods)
    }

    @Test
    fun `a mutation sends its hash over POST`() = runTest {
        client.mutations.persistedLongMutation(createUserInput)

        assertEquals(listOf("POST", "POST"), server.methods)
        assertTrue(server.isHashOnly(server.requests[0]))
    }

    @Test
    fun `a server that refuses GET gets the same hash-only request as a POST`() = runTest {
        server.getSupported = false

        val res = client.queries.persistedLongQuery("user-1")

        assertEquals("Alice Smith", res.getUser.name)
        assertEquals(listOf("GET", "POST", "POST"), server.methods)
        assertEquals(2, server.requests.size)
        assertTrue(server.isHashOnly(server.requests[0]))
        assertTrue(server.requests[1].containsKey("query"))
    }

    @Test
    fun `a server that refused GET is not asked with a GET again`() = runTest {
        server.getSupported = false
        client.queries.persistedLongQuery("user-1")
        server.methods.clear()

        client.queries.persistedLongQuery("user-2")

        assertEquals(listOf("POST"), server.methods)
    }

    @Test
    fun `a server without APQ answers the GET with a refusal, then gets the full query by POST`() = runTest {
        server.supported = false

        client.queries.persistedLongQuery("user-1")

        assertEquals(listOf("GET", "POST"), server.methods)
        assertTrue(server.requests[1].containsKey("query"))
        assertFalse(server.requests[1].containsKey("extensions"))
    }

    @Test
    fun `other GET failures propagate untouched, with no POST`() = runTest {
        server.getFailWith = IllegalStateException("network down")

        val e = assertFailsWith<IllegalStateException> { client.queries.persistedLongQuery("user-1") }
        assertEquals("network down", e.message)
        assertEquals(listOf("GET"), server.methods)
    }
}
