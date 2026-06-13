package dev.graphlink.kotlinclienttest

import dev.graphlink.kotlinclient.generated.client.GraphLinkClient
import dev.graphlink.kotlinclient.generated.inputs.CreateArticleInput
import dev.graphlink.kotlinclient.generated.inputs.UpdateArticleInput
import kotlinx.coroutines.test.runTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MutationsTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = Fixtures.newClient()
    }

    @Test
    fun createArticle_returnsCreatedArticle() = runTest {
        val res = client.mutations.createArticle(CreateArticleInput(title = "New Post", authorId = "2"))
        assertEquals("New Post", res.createArticle.title)
        assertEquals("2", res.createArticle.authorId)
        assertTrue(res.createArticle.id.isNotEmpty())
    }

    @Test
    fun updateArticle_updatesTitle() = runTest {
        val created = client.mutations.createArticle(CreateArticleInput(title = "Original Title", authorId = "1"))
        val res = client.mutations.updateArticle(UpdateArticleInput(id = created.createArticle.id, title = "Updated Title"))
        assertEquals(created.createArticle.id, res.updateArticle.id)
        assertEquals("Updated Title", res.updateArticle.title)
    }

    @Test
    fun deleteArticle_returnsTrueWhenArticleExists() = runTest {
        val created = client.mutations.createArticle(CreateArticleInput(title = "To Delete", authorId = "1"))
        val res = client.mutations.deleteArticle(created.createArticle.id)
        assertTrue(res.deleteArticle)
    }

    @Test
    fun deleteArticle_returnsFalseWhenArticleDoesNotExist() = runTest {
        val res = client.mutations.deleteArticle("missing-id")
        assertFalse(res.deleteArticle)
    }
}
