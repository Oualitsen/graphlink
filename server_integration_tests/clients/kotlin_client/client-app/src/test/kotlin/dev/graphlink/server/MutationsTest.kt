package dev.graphlink.server

import dev.graphlink.server.generated.client.GraphLinkClient
import dev.graphlink.server.generated.enums.Priority
import dev.graphlink.server.generated.inputs.CreateArticleFieldArgs
import dev.graphlink.server.generated.inputs.CreateArticleInput
import dev.graphlink.server.generated.inputs.UpdateArticleFieldArgs
import dev.graphlink.server.generated.inputs.UpdateArticleInput
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
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

    @Nested
    inner class CreateArticle {
        @Test
        fun returnsCreatedArticleWithGivenInput() = runTest {
            val res = client.mutations.createArticle(
                CreateArticleInput(title = "New Post", authorId = "2"),
                CreateArticleFieldArgs(2),
            )
            assertEquals("New Post", res.createArticle.title)
            assertEquals("2", res.createArticle.authorId)
            assertTrue(res.createArticle.id.isNotEmpty())
        }
    }

    @Nested
    inner class UpdateArticle {
        @Test
        fun updatesTitleAndReturnsArticle() = runTest {
            val created = client.mutations.createArticle(
                CreateArticleInput(title = "Original Title", authorId = "1"),
                CreateArticleFieldArgs(2),
            )
            val res = client.mutations.updateArticle(
                UpdateArticleInput(id = created.createArticle.id, title = "Updated Title"),
                UpdateArticleFieldArgs(2),
            )
            assertEquals(created.createArticle.id, res.updateArticle.id)
            assertEquals("Updated Title", res.updateArticle.title)
        }
    }

    @Nested
    inner class DeleteArticle {
        @Test
        fun returnsTrueWhenArticleExists() = runTest {
            val created = client.mutations.createArticle(
                CreateArticleInput(title = "To Delete", authorId = "1"),
                CreateArticleFieldArgs(2),
            )
            val res = client.mutations.deleteArticle(created.createArticle.id)
            assertTrue(res.deleteArticle)
        }

        @Test
        fun returnsFalseWhenArticleDoesNotExist() = runTest {
            val res = client.mutations.deleteArticle("missing-id")
            assertFalse(res.deleteArticle)
        }
    }

    @Nested
    inner class AckPriority {
        @Test
        fun enumMutationArgumentDeserializesReturnsConstantAck() = runTest {
            val res = client.mutations.ackPriority(Priority.HIGH)
            assertEquals("OK", res.ackPriority)
        }
    }
}
