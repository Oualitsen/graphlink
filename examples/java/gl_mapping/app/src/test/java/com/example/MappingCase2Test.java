package com.example;

import com.example.generated.inputs.CreatePersonInput;
import com.example.generated.types.Person;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.*;

/**
 * Case 2 — @glMapField aliases.
 * schema: CreatePersonInput @glMapsTo(type: "Person")
 *   fname: String! @glMapField(to: "firstName")
 *   lname: String! @glMapField(to: "lastName")
 *   email: String!
 *   # id missing → required param in toPerson()
 */
class MappingCase2Test {

    @Test
    void toPerson_mapsAliasedFields() {
        CreatePersonInput input = new CreatePersonInput("John", "Doe", "john@example.com");
        Person result = input.toPerson("user-1");

        assertThat(result.getFirstName()).isEqualTo("John");   // fname → firstName
        assertThat(result.getLastName()).isEqualTo("Doe");     // lname → lastName
        assertThat(result.getEmail()).isEqualTo("john@example.com");
    }

    @Test
    void toPerson_assignsRequiredIdParam() {
        CreatePersonInput input = new CreatePersonInput("Jane", "Smith", "jane@example.com");
        Person result = input.toPerson("person-42");

        assertThat(result.getId()).isEqualTo("person-42");
    }

    @Test
    void fromPerson_reversesAliases() {
        Person person = new Person("p-1", "Alice", "Cooper", "alice@example.com");
        CreatePersonInput result = CreatePersonInput.fromPerson(person);

        assertThat(result.getFname()).isEqualTo("Alice");    // firstName → fname
        assertThat(result.getLname()).isEqualTo("Cooper");   // lastName → lname
        assertThat(result.getEmail()).isEqualTo("alice@example.com");
    }

    @Test
    void toPerson_thenFromPerson_preservesAliasedFields() {
        CreatePersonInput original = new CreatePersonInput("Bob", "Marley", "bob@example.com");
        CreatePersonInput roundTrip = CreatePersonInput.fromPerson(original.toPerson("id-99"));

        assertThat(roundTrip.getFname()).isEqualTo(original.getFname());
        assertThat(roundTrip.getLname()).isEqualTo(original.getLname());
        assertThat(roundTrip.getEmail()).isEqualTo(original.getEmail());
    }
}
