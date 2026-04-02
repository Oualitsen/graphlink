package com.example;

import com.example.generated.inputs.CreateAddressInput;
import com.example.generated.types.Address;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.*;

/**
 * Case 1 — All fields match by name, no extras, no nullability mismatch.
 * schema: CreateAddressInput @glMapsTo(type: "Address")
 *   street: String!  city: String!  country: String!
 */
class MappingCase1Test {

    @Test
    void toAddress_mapsAllFieldsDirectly() {
        CreateAddressInput input = new CreateAddressInput("123 Main St", "Springfield", "US");
        Address result = input.toAddress();

        assertThat(result.getStreet()).isEqualTo("123 Main St");
        assertThat(result.getCity()).isEqualTo("Springfield");
        assertThat(result.getCountry()).isEqualTo("US");
    }

    @Test
    void fromAddress_mapsAllFieldsDirectly() {
        Address address = new Address("10 Elm St", "Shelbyville", "CA");
        CreateAddressInput result = CreateAddressInput.fromAddress(address);

        assertThat(result.getStreet()).isEqualTo("10 Elm St");
        assertThat(result.getCity()).isEqualTo("Shelbyville");
        assertThat(result.getCountry()).isEqualTo("CA");
    }

    @Test
    void toAddress_thenFromAddress_isSymmetric() {
        CreateAddressInput original = new CreateAddressInput("1 Loop", "Portland", "US");
        CreateAddressInput roundTrip = CreateAddressInput.fromAddress(original.toAddress());

        assertThat(roundTrip.getStreet()).isEqualTo(original.getStreet());
        assertThat(roundTrip.getCity()).isEqualTo(original.getCity());
        assertThat(roundTrip.getCountry()).isEqualTo(original.getCountry());
    }
}
