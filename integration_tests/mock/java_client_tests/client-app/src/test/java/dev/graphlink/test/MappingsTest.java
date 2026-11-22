package dev.graphlink.test;

import dev.graphlink.test.generated.inputs.MappedArticleDraftInput;
import dev.graphlink.test.generated.inputs.MappedArticleUpdateInput;
import dev.graphlink.test.generated.types.MappedArticle;
import dev.graphlink.test.generated.types.MappedArticleCard;
import dev.graphlink.test.generated.types.MappedArticleSummary;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class MappingsTest {

    private final MappedArticle article = new MappedArticle("a1", "Hello", "Body text", 7);
    private final MappedArticle unviewed = new MappedArticle("a2", "Quiet", "No readers", null);

    @Nested
    class TypeWithSeveralTargets {

        @Test
        void toMappedArticleSummaryRenamesTitleToHeadline() {
            MappedArticleSummary summary = article.toMappedArticleSummary();
            assertEquals("a1", summary.getId());
            assertEquals("Hello", summary.getHeadline());
        }

        @Test
        void toMappedArticleCardRenamesTitleToNameAndKeepsViews() {
            MappedArticleCard card = article.toMappedArticleCard(99);
            assertEquals("a1", card.getId());
            assertEquals("Hello", card.getName());
            assertEquals(7, card.getViews());
        }

        @Test
        void toMappedArticleCardUsesDefaultViewsWhenViewsIsNull() {
            MappedArticleCard card = unviewed.toMappedArticleCard(99);
            assertEquals("Quiet", card.getName());
            assertEquals(99, card.getViews());
        }

        @Test
        void toMappedArticleUpdateInputKeepsTitleAndTakesStatus() {
            MappedArticleUpdateInput update = article.toMappedArticleUpdateInput("PUBLISHED");
            assertEquals("a1", update.getId());
            assertEquals("Hello", update.getTitle());
            assertEquals("Body text", update.getBody());
            assertEquals("PUBLISHED", update.getStatus());
        }

        @Test
        void everyMappingReturnsANewObject() {
            assertNotSame(article, article.toMappedArticleSummary());
        }
    }

    @Nested
    class InputWithSeveralTargets {

        private final MappedArticleDraftInput draft = new MappedArticleDraftInput("Draft", "Text", 3);
        private final MappedArticleDraftInput bare = new MappedArticleDraftInput("Bare", "Nothing", null);

        @Test
        void toMappedArticleCopiesTheFieldsAndTakesId() {
            MappedArticle mapped = draft.toMappedArticle("d1");
            assertEquals("d1", mapped.getId());
            assertEquals("Draft", mapped.getTitle());
            assertEquals("Text", mapped.getBody());
            assertEquals(3, mapped.getViews());
        }

        @Test
        void toMappedArticleKeepsANullViews() {
            assertNull(bare.toMappedArticle("d2").getViews());
        }

        @Test
        void toMappedArticleUpdateInputTakesIdAndStatus() {
            MappedArticleUpdateInput update = draft.toMappedArticleUpdateInput("d1", "DRAFT");
            assertEquals("d1", update.getId());
            assertEquals("Draft", update.getTitle());
            assertEquals("Text", update.getBody());
            assertEquals("DRAFT", update.getStatus());
        }
    }
}
