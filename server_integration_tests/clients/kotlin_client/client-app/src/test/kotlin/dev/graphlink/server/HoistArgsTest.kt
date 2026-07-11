package dev.graphlink.server

import dev.graphlink.server.generated.client.GraphLinkClient
import dev.graphlink.server.generated.inputs.CatalogFieldArgs1
import dev.graphlink.server.generated.inputs.FeedFieldArgs
import dev.graphlink.server.generated.inputs.SearchFieldArgs
import dev.graphlink.server.generated.inputs.StoreFieldArgs
import kotlinx.coroutines.test.runTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class HoistArgsTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = Fixtures.newClient()
    }

    @Test
    fun manyRequiredHoistedArgsInputRenamedCatalogFieldArgs1OnCollision() = runTest {
        val catalog = client.queries.catalog(
            CatalogFieldArgs1(productsCategory = "books", productsLimit = 3, productsOffset = 0),
        ).catalog
        assertEquals(3, catalog.products.size)
        assertTrue(catalog.products.all { it.name.startsWith("books") })
    }

    @Test
    fun allOptionalHoistedArgsCanBeOmittedDefaultItemsLimit10() = runTest {
        val feed = client.queries.feed().feed
        assertEquals(10, feed.items.size)
    }

    @Test
    fun optionalHoistedArgsCanBeSupplied() = runTest {
        val feed = client.queries.feed(FeedFieldArgs(itemsLimit = 4, itemsSort = "z")).feed
        assertEquals(4, feed.items.size)
        assertTrue(feed.items.first().name.startsWith("z"))
    }

    @Test
    fun nestedDepthHoistingCollapsesIntoOneInput() = runTest {
        val store = client.queries.store(StoreFieldArgs(shelvesFloor = 2, productsLimit = 3)).store
        assertEquals(2, store.shelves.size)
        assertEquals(3, store.shelves.first().products.size)
    }

    @Test
    fun paramNameCollisionUsesFieldArgs1ForSyntheticArg() = runTest {
        val search = client.queries.search("q", SearchFieldArgs(hitsLimit = 3)).search
        assertEquals("q", search.id)
        assertEquals(3, search.hits.size)
    }
}
