package dev.graphlink.server

import dev.graphlink.server.generated.inputs.ArticleCreatedFieldArgs
import dev.graphlink.server.generated.inputs.ArticleUpdatedFieldArgs
import dev.graphlink.server.generated.inputs.CreateArticleFieldArgs
import dev.graphlink.server.generated.inputs.CreateArticleInput
import dev.graphlink.server.generated.inputs.UpdateArticleFieldArgs
import dev.graphlink.server.generated.inputs.UpdateArticleInput
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Nested
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.time.Duration.Companion.seconds

class SubscriptionsTest {

    @Nested
    inner class ArticleCreated {
        @Test
        fun emitsWhenAnArticleIsCreated() = runBlocking {
            val client = Fixtures.newClient()

            val eventDeferred = async {
                withTimeout(10.seconds) {
                    client.subscriptions.articleCreated(ArticleCreatedFieldArgs(2)).first()
                }
            }

            delay(300)

            val created = client.mutations.createArticle(
                CreateArticleInput(title = "Subscribed Post", authorId = "1"),
                CreateArticleFieldArgs(2),
            )

            val event = eventDeferred.await()
            assertEquals(created.createArticle.id, event.articleCreated.id)
            assertEquals("Subscribed Post", event.articleCreated.title)
        }
    }

    @Nested
    inner class ArticleUpdated {
        @Test
        fun emitsWhenTheMatchingArticleIsUpdated() = runBlocking {
            val client = Fixtures.newClient()

            val created = client.mutations.createArticle(
                CreateArticleInput(title = "Will Update", authorId = "2"),
                CreateArticleFieldArgs(2),
            )

            val eventDeferred = async {
                withTimeout(10.seconds) {
                    client.subscriptions
                        .articleUpdated(created.createArticle.id, ArticleUpdatedFieldArgs(2))
                        .first()
                }
            }

            delay(300)

            val updated = client.mutations.updateArticle(
                UpdateArticleInput(id = created.createArticle.id, title = "Updated via subscription"),
                UpdateArticleFieldArgs(2),
            )

            val event = eventDeferred.await()
            assertEquals(updated.updateArticle.id, event.articleUpdated.id)
            assertEquals("Updated via subscription", event.articleUpdated.title)
        }
    }
}
