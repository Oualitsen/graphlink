package dev.graphlink.server;

import dev.graphlink.server.generated.client.GraphLinkClient;
import dev.graphlink.server.generated.inputs.ArticleCreatedFieldArgs;
import dev.graphlink.server.generated.inputs.ArticleUpdatedFieldArgs;
import dev.graphlink.server.generated.inputs.CreateArticleFieldArgs;
import dev.graphlink.server.generated.inputs.CreateArticleInput;
import dev.graphlink.server.generated.inputs.UpdateArticleFieldArgs;
import dev.graphlink.server.generated.inputs.UpdateArticleInput;
import dev.graphlink.server.generated.types.ArticleCreatedResponse;
import dev.graphlink.server.generated.types.ArticleUpdatedResponse;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.assertEquals;

public class SubscriptionsTest {

    @Nested
    class ArticleCreated {
        @Test
        void emitsWhenAnArticleIsCreated() throws Exception {
            GraphLinkClient client = Fixtures.newClient();

            CompletableFuture<ArticleCreatedResponse> eventFuture =
                    client.subscriptions.articleCreated(new ArticleCreatedFieldArgs(2)).next().toFuture();

            Thread.sleep(300);

            var created = client.mutations.createArticle(
                    CreateArticleInput.builder().title("Subscribed Post").authorId("1").build(),
                    new CreateArticleFieldArgs(2)).block();

            var event = eventFuture.get(10, TimeUnit.SECONDS);
            assertEquals(created.getCreateArticle().getId(), event.getArticleCreated().getId());
            assertEquals("Subscribed Post", event.getArticleCreated().getTitle());
        }
    }

    @Nested
    class ArticleUpdated {
        @Test
        void emitsWhenTheMatchingArticleIsUpdated() throws Exception {
            GraphLinkClient client = Fixtures.newClient();

            var created = client.mutations.createArticle(
                    CreateArticleInput.builder().title("Will Update").authorId("2").build(),
                    new CreateArticleFieldArgs(2)).block();

            CompletableFuture<ArticleUpdatedResponse> eventFuture = client.subscriptions.articleUpdated(
                    created.getCreateArticle().getId(),
                    new ArticleUpdatedFieldArgs(2)).next().toFuture();

            Thread.sleep(300);

            var updated = client.mutations.updateArticle(
                    UpdateArticleInput.builder().id(created.getCreateArticle().getId()).title("Updated via subscription").build(),
                    new UpdateArticleFieldArgs(2)).block();

            var event = eventFuture.get(10, TimeUnit.SECONDS);
            assertEquals(updated.getUpdateArticle().getId(), event.getArticleUpdated().getId());
            assertEquals("Updated via subscription", event.getArticleUpdated().getTitle());
        }
    }
}
