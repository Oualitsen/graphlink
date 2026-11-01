package dev.graphlink.test

import kotlin.test.*

class GlHashTest {
    private val client = Helpers.newClient(ApqServer())

    @Test
    fun `hashes a query like a reference SHA-256`() {
        assertEquals("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", client.queries.glHash("abc"))
        assertEquals("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", client.queries.glHash(""))
    }

    @Test
    fun `hashes a real GraphQL document`() {
        assertEquals(
            "76c03fc2e5cc623d71d65ac35823728a3fd45da3b453349dafa9b6fc1d1b7abc",
            client.queries.glHash("query GetUser(\$id: ID!){getUser(id:\$id){id name}}"),
        )
    }

    @Test
    fun `is the same for repeated calls`() {
        val first = client.queries.glHash("query A{a}")
        assertEquals(first, client.queries.glHash("query A{a}"))
        assertNotEquals(first, client.queries.glHash("query B{b}"))
    }

    @Test
    fun `is shared by queries and mutations through the base class`() {
        assertEquals(client.queries.glHash("abc"), client.mutations.glHash("abc"))
    }
}
