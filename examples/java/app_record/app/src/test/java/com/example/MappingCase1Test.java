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

}
