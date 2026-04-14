package com.example;

import com.example.generated.inputs.CreateAddressInput;
import com.example.generated.types.Address;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.*;

/**
 * Case 1 — All fields match by name, no extras, no nullability mismatch.
 * Records use component accessors: street(), city(), country().
 */
class MappingCase1Test {

    @Test
    void toAddress_mapsAllFieldsDirectly() {
        CreateAddressInput input = new CreateAddressInput("123 Main St", "Springfield", "US");
        Address result = input.toAddress();

        assertThat(result.street()).isEqualTo("123 Main St");
        assertThat(result.city()).isEqualTo("Springfield");
        assertThat(result.country()).isEqualTo("US");
    }

    @Test
    void fromAddress_mapsAllFieldsDirectly() {
        Address address = new Address("10 Elm St", "Shelbyville", "CA");
        CreateAddressInput result = CreateAddressInput.fromAddress(address);

        assertThat(result.street()).isEqualTo("10 Elm St");
        assertThat(result.city()).isEqualTo("Shelbyville");
        assertThat(result.country()).isEqualTo("CA");
    }

    @Test
    void toAddress_thenFromAddress_isSymmetric() {
        CreateAddressInput original = new CreateAddressInput("1 Loop", "Portland", "US");
        CreateAddressInput roundTrip = CreateAddressInput.fromAddress(original.toAddress());

        assertThat(roundTrip.street()).isEqualTo(original.street());
        assertThat(roundTrip.city()).isEqualTo(original.city());
        assertThat(roundTrip.country()).isEqualTo(original.country());
    }
}
