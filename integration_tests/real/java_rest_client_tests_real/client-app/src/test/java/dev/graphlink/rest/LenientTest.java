package dev.graphlink.rest;

import static dev.graphlink.rest.Support.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.rest.generated.client.*;
import dev.graphlink.rest.generated.types.CatRest;
import dev.graphlink.rest.generated.types.DogRest;
import dev.graphlink.rest.generated.interfaces.HitRest;
import dev.graphlink.rest.generated.interfaces.PetRest;
import dev.graphlink.rest.generated.types.OwnerRest;
import dev.graphlink.rest.generated.types.ProductRest;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class LenientTest {
    private GraphLinkClient client;

    @BeforeEach
    void setUp() throws Exception {
        resetServer();
        client = newClient();
    }

    @Test
    void nullAndMissingFieldsOfNonNullSchemaFieldsDecodeAsNull() {
        ProductRest product = client.queries.lenientProduct();
        assertEquals("p1", product.getId());
        assertNull(product.getName());
        assertNull(product.getPrice());
        assertNull(product.getTags());
    }

    @Test
    void nestedObjectsAreLenientToo() {
        List<ProductRest> related = client.queries.lenientProduct().getRelated();
        assertEquals(2, related.size());
        assertEquals("p2", related.get(0).getId());
        assertNull(related.get(0).getName());
        assertNull(related.get(0).getRelated());
        assertEquals("Three", related.get(1).getName());
        assertEquals(3.5, related.get(1).getPrice());
        assertNull(related.get(1).getRelated());
    }

    @Test
    void listsOfObjectsDecode() {
        List<ProductRest> products = client.queries.lenientProducts();
        assertEquals(2, products.size());
        assertNull(products.get(0).getName());
        assertEquals("B", products.get(1).getName());
    }

    @Test
    void anEmptyBodyIsStillNullBecauseTheSchemaSaysSo() {
        assertNull(client.queries.lenientNothing());
    }

    @Test
    void theSameTypeWithoutTheDirectiveStillFailsOnTheSamePayload() {
        IllegalArgumentException error = assertThrows(IllegalArgumentException.class, () -> client.queries.strictProduct());
        assertEquals("Product.name is missing or null in the response", error.getMessage());
    }

    @Test
    void interfacesDecodeThroughTheirDiscriminatorWithMissingFields() {
        List<PetRest> pets = client.queries.lenientPets();
        assertEquals(3, pets.size());

        DogRest first = assertInstanceOf(DogRest.class, pets.get(0));
        assertEquals("d1", first.getId());
        assertNull(first.getName());
        assertNull(first.getBarks());

        CatRest second = assertInstanceOf(CatRest.class, pets.get(1));
        assertEquals("c1", second.getId());
        assertNull(second.getName());
        assertNull(second.getLives());

        DogRest third = assertInstanceOf(DogRest.class, pets.get(2));
        assertNull(third.getId());
        assertEquals("Rex", third.getName());
        assertTrue(third.getBarks());
    }

    @Test
    void theInterfaceWithoutTheDirectiveStillFailsOnTheSamePayload() {
        IllegalArgumentException error = assertThrows(IllegalArgumentException.class, () -> client.queries.strictPets());
        assertTrue(error.getMessage().endsWith("is missing or null in the response"), error.getMessage());
    }

    @Test
    void unionsDecodeThroughTheirDiscriminator() {
        List<HitRest> hits = client.queries.lenientHits();
        assertInstanceOf(ProductRest.class, hits.get(0));
        assertEquals("p1", ((ProductRest) hits.get(0)).getId());
        OwnerRest owner = assertInstanceOf(OwnerRest.class, hits.get(1));
        assertEquals("o1", owner.getId());
        assertNull(owner.getName());
    }

    @Test
    void aCachedLenientResultIsStoredAndDecodedTheSameWay() {
        GraphLinkClient cached = newClient(new InMemoryGraphLinkCacheStore());
        ProductRest first = cached.queries.lenientCached();
        ProductRest second = cached.queries.lenientCached();
        assertNull(first.getName());
        assertNull(second.getName());
        assertEquals(first.getRelated().size(), second.getRelated().size());
        assertEquals("Three", second.getRelated().get(1).getName());
    }
}
