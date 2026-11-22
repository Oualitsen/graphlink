package dev.graphlink.test

import dev.graphlink.test.generated.inputs.MappedArticleDraftInput
import dev.graphlink.test.generated.types.MappedArticle
import org.junit.jupiter.api.Nested
import kotlin.test.*

class MappingsTest {

    private val article = MappedArticle(id = "a1", title = "Hello", body = "Body text", views = 7)
    private val unviewed = MappedArticle(id = "a2", title = "Quiet", body = "No readers")

    @Nested
    inner class TypeWithSeveralTargets {

        @Test
        fun `toMappedArticleSummary renames title to headline`() {
            val summary = article.toMappedArticleSummary()
            assertEquals("a1", summary.id)
            assertEquals("Hello", summary.headline)
        }

        @Test
        fun `toMappedArticleCard renames title to name and keeps views`() {
            val card = article.toMappedArticleCard(99)
            assertEquals("a1", card.id)
            assertEquals("Hello", card.name)
            assertEquals(7, card.views)
        }

        @Test
        fun `toMappedArticleCard uses defaultViews when views is null`() {
            val card = unviewed.toMappedArticleCard(99)
            assertEquals("Quiet", card.name)
            assertEquals(99, card.views)
        }

        @Test
        fun `toMappedArticleUpdateInput keeps title and takes status`() {
            val update = article.toMappedArticleUpdateInput("PUBLISHED")
            assertEquals("a1", update.id)
            assertEquals("Hello", update.title)
            assertEquals("Body text", update.body)
            assertEquals("PUBLISHED", update.status)
        }

        @Test
        fun `every mapping returns a new object`() {
            assertNotSame<Any>(article, article.toMappedArticleSummary())
        }
    }

    @Nested
    inner class InputWithSeveralTargets {

        private val draft = MappedArticleDraftInput(title = "Draft", body = "Text", views = 3)
        private val bare = MappedArticleDraftInput(title = "Bare", body = "Nothing")

        @Test
        fun `toMappedArticle copies the fields and takes id`() {
            val mapped = draft.toMappedArticle("d1")
            assertEquals("d1", mapped.id)
            assertEquals("Draft", mapped.title)
            assertEquals("Text", mapped.body)
            assertEquals(3, mapped.views)
        }

        @Test
        fun `toMappedArticle keeps a null views`() {
            assertNull(bare.toMappedArticle("d2").views)
        }

        @Test
        fun `toMappedArticleUpdateInput takes id and status`() {
            val update = draft.toMappedArticleUpdateInput("d1", "DRAFT")
            assertEquals("d1", update.id)
            assertEquals("Draft", update.title)
            assertEquals("Text", update.body)
            assertEquals("DRAFT", update.status)
        }
    }
}
