package dev.graphlink.server

import dev.graphlink.server.generated.client.GraphLinkClient
import dev.graphlink.server.generated.inputs.GetArticleFieldArgs
import dev.graphlink.server.generated.inputs.GetAuthorAndArticleFieldArgs
import dev.graphlink.server.generated.inputs.GetAuthorFieldArgs
import dev.graphlink.server.generated.inputs.ListArticlesFieldArgs
import dev.graphlink.server.generated.inputs.ListAuthorsFieldArgs
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
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

    @Nested
    inner class GetAuthor {
        @Test
        fun returnsAuthorById() = runTest {
            val res = client.queries.getAuthor("1", GetAuthorFieldArgs(10))
            assertNotNull(res.getAuthor)
            assertEquals("1", res.getAuthor!!.id)
            assertEquals("Ramdane", res.getAuthor!!.name)
        }

        @Test
        fun returnsNullForUnknownId() = runTest {
            val res = client.queries.getAuthor("missing", GetAuthorFieldArgs(10))
            assertNull(res.getAuthor)
        }

        @Test
        fun articlesResolvedViaBatchDataLoaderMapping() = runTest {
            val res = client.queries.getAuthor("1", GetAuthorFieldArgs(10))
            val titles = res.getAuthor!!.articles!!.map { it.title }.toSet()
            assertTrue(titles.containsAll(setOf("GraphLink Basics", "Advanced GraphLink")))
        }

        @Test
        fun latestArticlesResolvedViaNonBatchMappingWithArguments() = runTest {
            val res = client.queries.getAuthor("1", GetAuthorFieldArgs(10))
            val titles = res.getAuthor!!.latestArticles!!.map { it.title }.toSet()
            assertTrue(titles.containsAll(setOf("GraphLink Basics", "Advanced GraphLink")))
        }
    }

    @Nested
    inner class GetAuthorWithoutArticle {
        @Test
        fun doesNotRequireLimitArgumentWhenArticlesNotProjected() = runTest {
            val res = client.queries.getAuthorWithoutArticle("1")
            assertNotNull(res.getAuthor)
            assertEquals("1", res.getAuthor!!.id)
            assertEquals("Ramdane", res.getAuthor!!.name)
        }
    }

    @Nested
    inner class GetArticle {
        @Test
        fun returnsArticleById() = runTest {
            val res = client.queries.getArticle("1", GetArticleFieldArgs(2))
            assertEquals("1", res.getArticle.id)
            assertEquals("GraphLink Basics", res.getArticle.title)
        }

        @Test
        fun authorResolvedViaNonBatchSchemaMapping() = runTest {
            val res = client.queries.getArticle("1", GetArticleFieldArgs(2))
            assertEquals("1", res.getArticle.author?.id)
            assertEquals("Ramdane", res.getArticle.author?.name)
        }
    }

    @Nested
    inner class GetAuthorAndArticle {
        @Test
        fun resolvesBothRootFieldsWithOwnArgsPlusSharedFragmentArgument() = runTest {
            val res = client.queries.getAuthorAndArticle("1", "3", GetAuthorAndArticleFieldArgs(1))
            assertEquals("1", res.author!!.id)
            assertEquals(1, res.author!!.latestArticles!!.size)
            assertEquals("3", res.article.id)
            assertEquals("Alice's First Post", res.article.title)
        }
    }

    @Nested
    inner class ListAuthorsAndListArticles {
        @Test
        fun listAuthorsReturnsAllAuthors() = runTest {
            val res = client.queries.listAuthors(ListAuthorsFieldArgs(10))
            assertTrue(res.listAuthors.map { it.id }.containsAll(listOf("1", "2")))
        }

        @Test
        fun listArticlesReturnsAllArticles() = runTest {
            val res = client.queries.listArticles(ListArticlesFieldArgs(2))
            assertTrue(res.listArticles.map { it.id }.contains("1"))
        }
    }
}
