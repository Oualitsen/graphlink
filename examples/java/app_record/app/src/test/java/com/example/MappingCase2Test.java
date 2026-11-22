package com.example;

import com.example.generated.inputs.CreatePersonInput;
import com.example.generated.types.Person;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.*;

/**
 * Case 2 — @glMapField aliases.
 * fname → firstName, lname → lastName; reversed in fromPerson().
 */
class MappingCase2Test {

    @Test
    void toPerson_mapsAliasedFields() {
        CreatePersonInput input = new CreatePersonInput("John", "Doe", "john@example.com");
        Person result = input.toPerson("user-1");

        assertThat(result.firstName()).isEqualTo("John");
        assertThat(result.lastName()).isEqualTo("Doe");
        assertThat(result.email()).isEqualTo("john@example.com");
    }

    @Test
    void toPerson_assignsRequiredIdParam() {
        CreatePersonInput input = new CreatePersonInput("Jane", "Smith", "jane@example.com");
        Person result = input.toPerson("person-42");

        assertThat(result.id()).isEqualTo("person-42");
    }

}
