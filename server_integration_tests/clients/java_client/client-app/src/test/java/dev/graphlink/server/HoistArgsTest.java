package dev.graphlink.server;

import dev.graphlink.server.generated.client.GraphLinkClient;
import dev.graphlink.server.generated.inputs.CatalogFieldArgs1;
import dev.graphlink.server.generated.inputs.FeedFieldArgs;
import dev.graphlink.server.generated.inputs.SearchFieldArgs;
import dev.graphlink.server.generated.inputs.StoreFieldArgs;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

public class HoistArgsTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = Fixtures.newClient();
    }

    @Test
    void manyRequiredHoistedArgsInputRenamedCatalogFieldArgs1OnCollision() {
        var catalog = client.queries.catalog(
                new CatalogFieldArgs1("books", 3, 0)).getCatalog();
        assertEquals(3, catalog.getProducts().size());
        assertTrue(catalog.getProducts().stream().allMatch(p -> p.getName().startsWith("books")));
    }

    @Test
    void allOptionalHoistedArgsCanBeOmittedDefaultItemsLimit10() {
        var feed = client.queries.feed(new FeedFieldArgs(null, null)).getFeed();
        assertEquals(10, feed.getItems().size());
    }

    @Test
    void optionalHoistedArgsCanBeSupplied() {
        var feed = client.queries.feed(new FeedFieldArgs(4, "z")).getFeed();
        assertEquals(4, feed.getItems().size());
        assertTrue(feed.getItems().get(0).getName().startsWith("z"));
    }

    @Test
    void nestedDepthHoistingCollapsesIntoOneInput() {
        var store = client.queries.store(new StoreFieldArgs(2, 3)).getStore();
        assertEquals(2, store.getShelves().size());
        assertEquals(3, store.getShelves().get(0).getProducts().size());
    }

    @Test
    void paramNameCollisionUsesFieldArgs1ForSyntheticArg() {
        var search = client.queries.search("q", new SearchFieldArgs(3)).getSearch();
        assertEquals("q", search.getId());
        assertEquals(3, search.getHits().size());
    }
}
