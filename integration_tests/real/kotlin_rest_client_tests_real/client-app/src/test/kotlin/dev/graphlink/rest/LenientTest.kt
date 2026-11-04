package dev.graphlink.rest

import dev.graphlink.rest.generated.client.*
import dev.graphlink.rest.generated.interfaces.HitRest
import dev.graphlink.rest.generated.interfaces.PetRest
import dev.graphlink.rest.generated.types.CatRest
import dev.graphlink.rest.generated.types.DogRest
import dev.graphlink.rest.generated.types.OwnerRest
import dev.graphlink.rest.generated.types.ProductRest
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LenientTest {
    private lateinit var client: GraphLinkClient

    @BeforeEach
    fun setUp() {
        resetServer()
        client = newClient()
    }

    @Test
    fun nullAndMissingFieldsOfNonNullSchemaFieldsDecodeAsNull() = runBlocking {
        val product = client.queries.lenientProduct()
        assertEquals("p1", product.id)
        assertNull(product.name)
        assertNull(product.price)
        assertNull(product.tags)
    }

    @Test
    fun nestedObjectsAreLenientToo() = runBlocking {
        val related = client.queries.lenientProduct().related!!
        assertEquals(2, related.size)
        assertEquals("p2", related[0].id)
        assertNull(related[0].name)
        assertNull(related[0].related)
        assertEquals("Three", related[1].name)
        assertEquals(3.5, related[1].price)
        assertNull(related[1].related)
    }

    @Test
    fun listsOfObjectsDecode() = runBlocking {
        val products: List<ProductRest> = client.queries.lenientProducts()
        assertEquals(2, products.size)
        assertNull(products[0].name)
        assertEquals("B", products[1].name)
    }

    @Test
    fun anEmptyBodyIsStillNullBecauseTheSchemaSaysSo() = runBlocking {
        assertNull(client.queries.lenientNothing())
    }

    @Test
    fun theSameTypeWithoutTheDirectiveStillFailsOnTheSamePayload() = runBlocking {
        val error = assertFailsWith<IllegalArgumentException> { client.queries.strictProduct() }
        assertEquals("Product.name is missing or null in the response", error.message)
        Unit
    }

    @Test
    fun interfacesDecodeThroughTheirDiscriminatorWithMissingFields() = runBlocking {
        val pets: List<PetRest> = client.queries.lenientPets()
        assertEquals(3, pets.size)

        val first = assertIs<DogRest>(pets[0])
        assertEquals("d1", first.id)
        assertNull(first.name)
        assertNull(first.barks)

        val second = assertIs<CatRest>(pets[1])
        assertEquals("c1", second.id)
        assertNull(second.name)
        assertNull(second.lives)

        val third = assertIs<DogRest>(pets[2])
        assertNull(third.id)
        assertEquals("Rex", third.name)
        assertEquals(true, third.barks)
    }

    @Test
    fun theInterfaceWithoutTheDirectiveStillFailsOnTheSamePayload() = runBlocking {
        val error = assertFailsWith<IllegalArgumentException> { client.queries.strictPets() }
        assertTrue(error.message!!.endsWith("is missing or null in the response"), error.message)
        Unit
    }

    @Test
    fun unionsDecodeThroughTheirDiscriminator() = runBlocking {
        val hits: List<HitRest> = client.queries.lenientHits()
        assertEquals("p1", assertIs<ProductRest>(hits[0]).id)
        val owner = assertIs<OwnerRest>(hits[1])
        assertEquals("o1", owner.id)
        assertNull(owner.name)
    }

    @Test
    fun aCachedLenientResultIsStoredAndDecodedTheSameWay() = runBlocking {
        val cached = newClient(store = InMemoryGraphLinkCacheStore())
        val first = cached.queries.lenientCached()
        val second = cached.queries.lenientCached()
        assertNull(first.name)
        assertNull(second.name)
        assertEquals(first.related!!.size, second.related!!.size)
        assertEquals("Three", second.related!![1].name)
    }
}
