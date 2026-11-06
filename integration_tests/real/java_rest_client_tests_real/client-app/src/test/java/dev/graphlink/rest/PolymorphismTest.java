package dev.graphlink.rest;

import static dev.graphlink.rest.Support.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.rest.generated.client.*;
import dev.graphlink.rest.generated.interfaces.Hit;
import dev.graphlink.rest.generated.interfaces.Pet;
import dev.graphlink.rest.generated.types.Cat;
import dev.graphlink.rest.generated.types.Dog;
import dev.graphlink.rest.generated.types.Kennel;
import dev.graphlink.rest.generated.types.Owner;
import dev.graphlink.rest.generated.types.Product;
import java.util.List;
import java.util.function.Supplier;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class PolymorphismTest {
    private GraphLinkClient client;

    @BeforeEach
    void setUp() throws Exception {
        resetServer();
        client = newClient();
    }

    private static String failureOf(Supplier<?> call) {
        RuntimeException error = assertThrows(RuntimeException.class, call::get);
        return String.valueOf(error.getMessage());
    }

    @Test
    void interfaceAndUnionFieldsInsideAnObject() {
        Kennel kennel = client.queries.kennel();
        assertInstanceOf(Dog.class, kennel.getResident());
        assertTrue(((Dog) kennel.getResident()).getBarks());
        assertInstanceOf(Product.class, kennel.getHit());
        assertEquals("Pen", ((Product) kennel.getHit()).getName());
    }

    @Test
    void listsOfInterfacesAndUnionsInsideAnObject() {
        Kennel kennel = client.queries.kennel();
        assertInstanceOf(Dog.class, kennel.getFeatured().get(0));
        assertInstanceOf(Cat.class, kennel.getFeatured().get(1));
        assertEquals(9, ((Cat) kennel.getFeatured().get(1)).getLives());
        assertInstanceOf(Product.class, kennel.getHits().get(0));
        assertInstanceOf(Owner.class, kennel.getHits().get(1));
    }

    @Test
    void nullElementsInAListOfInterfaces() {
        List<Pet> mixed = client.queries.kennel().getMixed();
        assertEquals(3, mixed.size());
        assertInstanceOf(Dog.class, mixed.get(0));
        assertNull(mixed.get(1));
        assertInstanceOf(Cat.class, mixed.get(2));
    }

    @Test
    void nullPolymorphicFields() {
        Kennel empty = client.queries.shelter().getKennels().get(1);
        assertNull(empty.getResident());
        assertTrue(empty.getFeatured().isEmpty());
        assertNull(empty.getMixed());
        assertNull(empty.getHit());
        assertNull(empty.getHits());
    }

    @Test
    void twoLevelsDeep() {
        var shelter = client.queries.shelter();
        assertEquals(2, shelter.getKennels().size());
        assertInstanceOf(Dog.class, shelter.getKennels().get(0).getResident());
        assertEquals("Tom", shelter.getKennels().get(0).getFeatured().get(1).getName());
    }

    @Test
    void nullableElementsKeepNull() {
        List<Pet> pets = client.queries.petsNullable();
        assertEquals(3, pets.size());
        assertInstanceOf(Dog.class, pets.get(0));
        assertNull(pets.get(1));
        assertInstanceOf(Cat.class, pets.get(2));
    }

    @Test
    void optionalListDecodesAJsonNullAsNull() {
        assertNull(client.queries.petsOptional());
    }

    @Test
    void throughResponsePath() {
        List<Pet> pets = client.queries.petsWrapped();
        assertInstanceOf(Dog.class, pets.get(0));
        assertInstanceOf(Cat.class, pets.get(1));
    }

    @Test
    void fromAMutation() {
        Pet pet = client.mutations.adoptPet("c9");
        assertInstanceOf(Cat.class, pet);
        assertEquals("c9", pet.getId());
        assertEquals("Adopted", pet.getName());
    }

    @Test
    void fromACachedOperation() {
        Pet first = client.queries.cachedPet("d7");
        Pet second = client.queries.cachedPet("d7");
        assertInstanceOf(Dog.class, first);
        assertEquals("Rex1", first.getName());
        assertEquals("Rex1", second.getName());
        assertEquals("Rex1", client.queries.cachedPet("d8").getName());
    }

    @Test
    void discriminatorKeyAbsent() {
        String message = failureOf(() -> client.queries.petNoKind());
        assertTrue(message.contains("Pet") && message.contains("kind"), message);
    }

    @Test
    void discriminatorNull() {
        String message = failureOf(() -> client.queries.petNullKind());
        assertTrue(message.contains("Pet") && message.contains("kind"), message);
    }

    @Test
    void unknownKeysInsideAMemberAreIgnored() {
        Pet pet = client.queries.petExtraKeys();
        assertInstanceOf(Dog.class, pet);
        assertEquals("Rex", pet.getName());
    }

    @Test
    void aMemberMissingARequiredFieldNamesTheField() {
        String message = failureOf(() -> client.queries.petMissingField());
        assertTrue(message.contains("barks"), message);
    }
}
