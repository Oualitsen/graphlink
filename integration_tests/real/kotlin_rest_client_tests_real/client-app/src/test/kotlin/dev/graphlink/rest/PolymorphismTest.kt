package dev.graphlink.rest

import dev.graphlink.rest.generated.client.*
import dev.graphlink.rest.generated.interfaces.*
import dev.graphlink.rest.generated.types.*
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFails
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

class PolymorphismTest {
    private lateinit var client: GraphLinkClient

    @BeforeEach
    fun setUp() {
        resetServer()
        client = newClient()
    }

    private fun failureOf(block: suspend () -> Unit): String = assertFails { runBlocking { block() } }.message ?: ""

    @Test
    fun interfaceAndUnionFieldsInsideAnObject() = runBlocking<Unit> {
        val kennel = client.queries.kennel()
        assertIs<Dog>(kennel.resident)
        assertTrue((kennel.resident as Dog).barks)
        assertIs<Product>(kennel.hit)
        assertEquals("Pen", (kennel.hit as Product).name)
    }

    @Test
    fun listsOfInterfacesAndUnionsInsideAnObject() = runBlocking<Unit> {
        val kennel = client.queries.kennel()
        assertIs<Dog>(kennel.featured[0])
        assertIs<Cat>(kennel.featured[1])
        assertEquals(9, (kennel.featured[1] as Cat).lives)
        assertIs<Product>(kennel.hits!![0])
        assertIs<Owner>(kennel.hits!![1])
    }

    @Test
    fun nullElementsInAListOfInterfaces() = runBlocking<Unit> {
        val mixed = client.queries.kennel().mixed!!
        assertEquals(3, mixed.size)
        assertIs<Dog>(mixed[0])
        assertNull(mixed[1])
        assertIs<Cat>(mixed[2])
    }

    @Test
    fun nullPolymorphicFields() = runBlocking<Unit> {
        val empty = client.queries.shelter().kennels[1]
        assertNull(empty.resident)
        assertTrue(empty.featured.isEmpty())
        assertNull(empty.mixed)
        assertNull(empty.hit)
        assertNull(empty.hits)
    }

    @Test
    fun twoLevelsDeep() = runBlocking<Unit> {
        val shelter = client.queries.shelter()
        assertEquals(2, shelter.kennels.size)
        assertIs<Dog>(shelter.kennels[0].resident)
        assertEquals("Tom", (shelter.kennels[0].featured[1] as Cat).name)
    }

    @Test
    fun nullableElementsKeepNull() = runBlocking<Unit> {
        val pets = client.queries.petsNullable()
        assertEquals(3, pets.size)
        assertIs<Dog>(pets[0])
        assertNull(pets[1])
        assertIs<Cat>(pets[2])
    }

    @Test
    fun optionalListDecodesAJsonNullAsNull() = runBlocking<Unit> {
        assertNull(client.queries.petsOptional())
    }

    @Test
    fun throughResponsePath() = runBlocking<Unit> {
        val pets = client.queries.petsWrapped()
        assertIs<Dog>(pets[0])
        assertIs<Cat>(pets[1])
    }

    @Test
    fun fromAMutation() = runBlocking<Unit> {
        val pet = client.mutations.adoptPet(id = "c9")
        assertIs<Cat>(pet)
        assertEquals("c9", pet.id)
        assertEquals("Adopted", pet.name)
    }

    @Test
    fun fromACachedOperation() = runBlocking<Unit> {
        val first = client.queries.cachedPet(id = "d7")
        val second = client.queries.cachedPet(id = "d7")
        assertIs<Dog>(first)
        assertEquals("Rex1", first.name)
        assertEquals("Rex1", second!!.name)
        assertEquals("Rex1", client.queries.cachedPet(id = "d8")!!.name)
    }

    @Test
    fun discriminatorKeyAbsent() {
        val message = failureOf { client.queries.petNoKind() }
        assertTrue(message.contains("Pet") && message.contains("kind"), message)
    }

    @Test
    fun discriminatorNull() {
        val message = failureOf { client.queries.petNullKind() }
        assertTrue(message.contains("Pet") && message.contains("kind"), message)
    }

    @Test
    fun unknownKeysInsideAMemberAreIgnored() = runBlocking<Unit> {
        val pet = client.queries.petExtraKeys()
        assertIs<Dog>(pet)
        assertEquals("Rex", pet.name)
    }

    @Test
    fun aMemberMissingARequiredFieldNamesTheField() {
        val message = failureOf { client.queries.petMissingField() }
        assertTrue(message.contains("barks"), message)
    }
}
