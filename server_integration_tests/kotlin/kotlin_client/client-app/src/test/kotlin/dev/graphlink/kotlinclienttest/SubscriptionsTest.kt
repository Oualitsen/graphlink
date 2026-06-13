package dev.graphlink.kotlinclienttest

import dev.graphlink.kotlinclient.generated.client.GraphLinkClient
import dev.graphlink.kotlinclient.generated.inputs.CreateArticleInput
import dev.graphlink.kotlinclient.generated.inputs.UpdateArticleInput
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.time.Duration.Companion.seconds

class SubscriptionsTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = Fixtures.newClient()
    }

    @Test
    fun articleCreated_emitsWhenArticleIsCreated() = runBlocking {
        val eventDeferred = async { client.subscriptions.articleCreated().first() }

        // give the subscription a moment to register before triggering the mutation
        delay(300)

        val created = client.mutations.createArticle(CreateArticleInput(title = "Subscribed Post", authorId = "1"))

        val event = withTimeout(10.seconds) { eventDeferred.await() }
        assertEquals(created.createArticle.id, event.articleCreated.id)
        assertEquals("Subscribed Post", event.articleCreated.title)
    }

    @Test
    fun articleUpdated_emitsForMatchingArticle() = runBlocking {
        val created = client.mutations.createArticle(CreateArticleInput(title = "Will Update", authorId = "2"))

        val eventDeferred = async { client.subscriptions.articleUpdated(created.createArticle.id).first() }

        delay(300)

        val updated = client.mutations.updateArticle(
            UpdateArticleInput(id = created.createArticle.id, title = "Updated via subscription")
        )

        val event = withTimeout(10.seconds) { eventDeferred.await() }
        assertEquals(updated.updateArticle.id, event.articleUpdated.id)
        assertEquals("Updated via subscription", event.articleUpdated.title)
    }
}
