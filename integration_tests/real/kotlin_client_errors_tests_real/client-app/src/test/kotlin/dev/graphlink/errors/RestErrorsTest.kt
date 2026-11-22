package dev.graphlink.errors

import dev.graphlink.errors.generated.client.GraphLinkClient
import dev.graphlink.errors.generated.client.GraphLinkDomainError
import dev.graphlink.errors.generated.client.RestError
import dev.graphlink.errors.generated.errors.ItemConflict
import dev.graphlink.errors.generated.errors.ItemNotFound
import dev.graphlink.errors.generated.errors.RateLimited
import dev.graphlink.errors.generated.errors.Teapot
import dev.graphlink.errors.generated.inputs.ItemInput
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.fail

class RestErrorsTest {
    private val client = GraphLinkClient.create("http://127.0.0.1:9930/graphql", "http://127.0.0.1:9930")

    private fun thrownBy(call: suspend () -> Any?): Throwable {
        try {
            runBlocking { call() }
        } catch (e: Throwable) {
            return e
        }
        fail("expected an exception")
    }

    @Test
    fun aSuccessfulCallReturnsItsData() = runBlocking<Unit> {
        assertEquals("Item 1", client.queries.item("1").name)
    }

    @Test
    fun aStatusOnlyErrorIsThrownWithTheFieldsOfTheBody() {
        val e = thrownBy { client.queries.item("missing") }
        assertIs<ItemNotFound>(e)
        assertIs<GraphLinkDomainError>(e)
        assertEquals("missing", e.id)
        assertEquals("Item missing not found", e.message)
    }

    @Test
    fun itCanBeCaughtByType() {
        var caught = ""
        try {
            runBlocking { client.queries.item("conflict") }
        } catch (e: ItemConflict) {
            caught = e.reason
        }
        assertEquals("duplicate", caught)
    }

    @Test
    fun aStatusWithItsOwnValueMatchesTheBodyCode() {
        val e = thrownBy { client.queries.item("conflict") }
        assertIs<ItemConflict>(e)
        assertEquals("Conflict", e.message)
    }

    @Test
    fun aCustomFieldPathIsReadFromTheBody() {
        val e = thrownBy { client.queries.item("rate") }
        assertIs<RateLimited>(e)
        assertEquals(30, e.retryAfter)
    }

    @Test
    fun aStatusOnlyErrorDoesNotNeedAJsonBody() {
        assertIs<Teapot>(thrownBy { client.queries.item("teapot") })
    }

    @Test
    fun aStatusOnlyErrorWithAnHtmlBodyStillMatchesByStatus() {
        val e = thrownBy { client.queries.item("html-404") }
        assertIs<ItemNotFound>(e)
        assertNull(e.id)
    }

    @Test
    fun aMutationThrowsItsDeclaredError() {
        val e = thrownBy { client.mutations.createItem(ItemInput(name = "dup")) }
        assertIs<ItemConflict>(e)
        assertEquals("name taken", e.reason)
    }

    @Test
    fun aMutationReturnsItsData() = runBlocking<Unit> {
        assertEquals("new", client.mutations.createItem(ItemInput(name = "fresh")).id)
    }

    private fun fallsBack(id: String, status: Int) {
        val e = thrownBy { client.queries.item(id) }
        assertIs<RestError>(e, id)
        assertFalse(e is GraphLinkDomainError, id)
        assertEquals(status, e.status)
    }

    @Test
    fun aBodyMissingARequiredFieldKeepsRestError() = fallsBack("conflict-no-reason", 409)

    @Test
    fun aCodeTheClientDoesNotKnowKeepsRestError() = fallsBack("conflict-other", 409)

    @Test
    fun aMistypedFieldKeepsRestError() = fallsBack("rate-bad", 429)

    @Test
    fun aProxyErrorWithAnHtmlBodyKeepsRestError() = fallsBack("bad-gateway", 502)

    @Test
    fun anOperationWithoutThrowsKeepsRestError() {
        val e = thrownBy { client.queries.itemPlain("x") }
        assertIs<RestError>(e)
        assertEquals(404, e.status)
    }
}
