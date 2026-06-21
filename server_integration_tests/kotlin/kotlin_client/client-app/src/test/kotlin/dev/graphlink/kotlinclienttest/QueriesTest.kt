package dev.graphlink.kotlinclienttest

import dev.graphlink.kotlinclient.generated.client.GraphLinkClient
import kotlinx.coroutines.test.runTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class QueriesTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = Fixtures.newClient()
    }

    @Test
    fun getAuthor_returnsAuthorById() = runTest {
        val res = client.queries.getAuthor("1")
        assertNotNull(res.getAuthor)
        assertEquals("1", res.getAuthor!!.id)
        assertEquals("Ramdane", res.getAuthor!!.name)
    }

    @Test
    fun getAuthor_returnsNullForUnknownId() = runTest {
        val res = client.queries.getAuthor("missing")
        assertNull(res.getAuthor)
    }

    @Test
    fun getAuthor_articlesResolvedViaBatchMapping() = runTest {
        val res = client.queries.getAuthor("1")
        val titles = res.getAuthor!!.articles?.map { it.title }?.toSet()
        assertTrue(titles?.containsAll(setOf("GraphLink Basics", "Advanced GraphLink")) ?: false)
    }

    @Test
    fun getArticle_returnsArticleById() = runTest {
        val res = client.queries.getArticle("1")
        assertEquals("1", res.getArticle.id)
        assertEquals("GraphLink Basics", res.getArticle.title)
    }

    @Test
    fun getArticle_authorResolvedViaSchemaMapping() = runTest {
        val res = client.queries.getArticle("1")
        assertEquals("1", res.getArticle.author?.id)
        assertEquals("Ramdane", res.getArticle.author?.name)
    }

    @Test
    fun listAuthors_returnsAllAuthors() = runTest {
        val res = client.queries.listAuthors()
        assertEquals(setOf("1", "2"), res.listAuthors.map { it.id }.toSet())
    }

    @Test
    fun listArticles_returnsAllArticles() = runTest {
        val res = client.queries.listArticles()
        assert(res.listArticles.any { it.id == "1" })
    }
}
