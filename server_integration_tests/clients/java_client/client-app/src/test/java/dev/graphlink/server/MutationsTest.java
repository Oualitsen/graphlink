package dev.graphlink.server;

import dev.graphlink.server.generated.client.GraphLinkClient;
import dev.graphlink.server.generated.enums.Priority;
import dev.graphlink.server.generated.inputs.CreateArticleFieldArgs;
import dev.graphlink.server.generated.inputs.CreateArticleInput;
import dev.graphlink.server.generated.inputs.UpdateArticleFieldArgs;
import dev.graphlink.server.generated.inputs.UpdateArticleInput;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

public class MutationsTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = Fixtures.newClient();
    }

    @Nested
    class CreateArticle {
        @Test
        void returnsCreatedArticleWithGivenInput() {
            var res = client.mutations.createArticle(
                    CreateArticleInput.builder().title("New Post").authorId("2").build(),
                    new CreateArticleFieldArgs(2));
            assertEquals("New Post", res.getCreateArticle().getTitle());
            assertEquals("2", res.getCreateArticle().getAuthorId());
            assertFalse(res.getCreateArticle().getId().isEmpty());
        }
    }

    @Nested
    class UpdateArticle {
        @Test
        void updatesTitleAndReturnsArticle() {
            var created = client.mutations.createArticle(
                    CreateArticleInput.builder().title("Original Title").authorId("1").build(),
                    new CreateArticleFieldArgs(2));
            var res = client.mutations.updateArticle(
                    UpdateArticleInput.builder().id(created.getCreateArticle().getId()).title("Updated Title").build(),
                    new UpdateArticleFieldArgs(2));
            assertEquals(created.getCreateArticle().getId(), res.getUpdateArticle().getId());
            assertEquals("Updated Title", res.getUpdateArticle().getTitle());
        }
    }

    @Nested
    class DeleteArticle {
        @Test
        void returnsTrueWhenArticleExists() {
            var created = client.mutations.createArticle(
                    CreateArticleInput.builder().title("To Delete").authorId("1").build(),
                    new CreateArticleFieldArgs(2));
            var res = client.mutations.deleteArticle(created.getCreateArticle().getId());
            assertTrue(res.getDeleteArticle());
        }

        @Test
        void returnsFalseWhenArticleDoesNotExist() {
            var res = client.mutations.deleteArticle("missing-id");
            assertFalse(res.getDeleteArticle());
        }
    }

    @Nested
    class AckPriority {
        @Test
        void enumMutationArgumentDeserializesReturnsConstantAck() {
            var res = client.mutations.ackPriority(Priority.HIGH);
            assertEquals("OK", res.getAckPriority());
        }
    }
}
