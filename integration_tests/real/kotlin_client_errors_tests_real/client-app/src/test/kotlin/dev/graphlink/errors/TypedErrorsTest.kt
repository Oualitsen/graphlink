package dev.graphlink.errors

import dev.graphlink.errors.generated.client.GraphLinkClient
import dev.graphlink.errors.generated.client.GraphLinkDomainError
import dev.graphlink.errors.generated.client.GraphLinkException
import dev.graphlink.errors.generated.enums.Reason
import dev.graphlink.errors.generated.errors.ArticleNotFound
import dev.graphlink.errors.generated.errors.Banned
import dev.graphlink.errors.generated.errors.Forbidden
import dev.graphlink.errors.generated.errors.TitleTaken
import dev.graphlink.errors.generated.inputs.ArticleInput
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.fail

class TypedErrorsTest {
    private val client = GraphLinkClient.create("http://127.0.0.1:9930/graphql")

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
        assertEquals("1", client.queries.article("1").article?.id)
    }

    @Test
    fun aDeclaredErrorIsThrownAsItsClassWithItsFields() {
        val e = thrownBy { client.queries.article("missing") }
        assertIs<ArticleNotFound>(e)
        assertIs<GraphLinkDomainError>(e)
        assertEquals("missing", e.id)
        assertEquals("Article missing not found", e.message)
    }

    @Test
    fun itCanBeCaughtByType() {
        var caught = ""
        try {
            runBlocking { client.queries.article("missing") }
        } catch (e: ArticleNotFound) {
            caught = e.id
        }
        assertEquals("missing", caught)
    }

    @Test
    fun anErrorMatchedOnACustomFieldAndValue() {
        val e = thrownBy { client.queries.article("forbidden") }
        assertIs<Forbidden>(e)
        assertEquals("No access", e.message)
    }

    @Test
    fun anErrorOfAnotherRootField() {
        assertIs<Forbidden>(thrownBy { client.queries.secret() })
    }

    @Test
    fun fallbacksKeepTheException() {
        for (id in listOf("other-code", "no-field", "no-path", "no-extensions")) {
            val e = thrownBy { client.queries.article(id) }
            assertIs<GraphLinkException>(e, id)
            assertFalse(e is GraphLinkDomainError, id)
        }
    }

    @Test
    fun anUnknownCodeKeepsItsMessage() {
        val e = thrownBy { client.queries.article("other-code") }
        assertIs<GraphLinkException>(e)
        assertEquals("A new error", e.errors[0].message)
    }

    @Test
    fun anOperationWithoutThrowsKeepsTheException() {
        val e = thrownBy { client.queries.plain("1") }
        assertIs<GraphLinkException>(e)
        assertFalse(e is GraphLinkDomainError)
    }

    @Test
    fun aCombinedQueryKeepsTheException() {
        val e = thrownBy { client.queries.pair() }
        assertIs<GraphLinkException>(e)
        assertEquals<Any?>(listOf("first"), e.errors[0].path)
    }

    @Test
    fun aCaptureErrorsOperationReturnsTheErrors() = runBlocking<Unit> {
        val res = client.queries.captured()
        assertNotNull(res.errors)
        assertEquals("ArticleNotFound", res.errors!![0].extensions!!["code"])
    }

    @Test
    fun aMutationReturnsItsData() = runBlocking<Unit> {
        assertEquals("fresh", client.mutations.createArticle(ArticleInput(title = "fresh")).createArticle?.id)
    }

    @Test
    fun aDeclaredErrorCarriesAListField() {
        val e = thrownBy { client.mutations.createArticle(ArticleInput(title = "taken")) }
        assertIs<TitleTaken>(e)
        assertEquals("taken", e.title)
        assertEquals(listOf("taken-2"), e.suggestions)
    }

    @Test
    fun anErrorWithItsOwnValueAnEnumAndAnOptionalField() {
        val e = thrownBy { client.mutations.createArticle(ArticleInput(title = "banned")) }
        assertIs<Banned>(e)
        assertEquals(Reason.SPAM, e.reason)
        assertEquals(5, e.until)
    }
}
