package com.example;

import com.example.generated.inputs.CreateOrderInput;
import com.example.generated.inputs.PhoneInput;
import com.example.generated.inputs.TagInput;
import com.example.generated.types.Order;
import com.example.generated.types.Phone;
import com.example.generated.types.Tag;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * Case 6 — Lists.
 * schema: CreateOrderInput @glMapsTo(type: "Order")
 *   keywords: [String!]!        → direct copy (non-null)
 *   notes: [String!]            → direct copy (nullable)
 *   tags: [TagInput!]!          → stream.map(e -> e.toTag())
 *   optionalTags: [TagInput!]   → null-guarded stream.map
 *   phones: [PhoneInput!]!      → unmapped, required param
 *   optionalPhones: [PhoneInput!] → unmapped, required param (nullable)
 *   # id missing → required param
 */
class MappingCase6Test {

    private static List<PhoneInput> phoneInputs() {
        return Arrays.asList(new PhoneInput("555-1234", "1"), new PhoneInput("555-5678", "44"));
    }

    private static List<Phone> phones() {
        return Arrays.asList(new Phone("555-1234", "1"), new Phone("555-5678", "44"));
    }

    // -------------------------------------------------------------------------
    // toOrder — basic mapping
    // -------------------------------------------------------------------------

    @Test
    void toOrder_copiesKeywordsDirectly() {
        List<String> kw = Arrays.asList("alpha", "beta");
        CreateOrderInput input = new CreateOrderInput(
                kw,
                null,
                Arrays.asList(new TagInput("t1", "Sale")),
                null,
                phoneInputs(),
                null);

        Order result = input.toOrder("o-1", phones(), null);

        assertThat(result.getKeywords()).containsExactly("alpha", "beta");
    }

    @Test
    void toOrder_copiesNullableNotesWhenPresent() {
        CreateOrderInput input = new CreateOrderInput(
                Arrays.asList("k"),
                Arrays.asList("note1"),
                Arrays.asList(new TagInput("t1", "Sale")),
                null,
                phoneInputs(),
                null);

        Order result = input.toOrder("o-2", phones(), null);

        assertThat(result.getNotes()).containsExactly("note1");
    }

    @Test
    void toOrder_notesAreNullWhenInputNotesAreNull() {
        CreateOrderInput input = new CreateOrderInput(
                Arrays.asList("k"),
                null,
                Arrays.asList(new TagInput("t1", "Sale")),
                null,
                phoneInputs(),
                null);

        Order result = input.toOrder("o-3", phones(), null);

        assertThat(result.getNotes()).isNull();
    }

    @Test
    void toOrder_mapsMappedTagsViaStream() {
        CreateOrderInput input = new CreateOrderInput(
                Arrays.asList("k"),
                null,
                Arrays.asList(new TagInput("t1", "Flash"), new TagInput("t2", "Promo")),
                null,
                phoneInputs(),
                null);

        Order result = input.toOrder("o-4", phones(), null);

        assertThat(result.getTags()).hasSize(2);
        assertThat(result.getTags().get(0).getId()).isEqualTo("t1");
        assertThat(result.getTags().get(0).getLabel()).isEqualTo("Flash");
        assertThat(result.getTags().get(1).getId()).isEqualTo("t2");
    }

    @Test
    void toOrder_mapsNullableOptionalTagsWhenPresent() {
        CreateOrderInput input = new CreateOrderInput(
                Arrays.asList("k"),
                null,
                Arrays.asList(new TagInput("t1", "A")),
                Arrays.asList(new TagInput("t2", "B")),
                phoneInputs(),
                null);

        Order result = input.toOrder("o-5", phones(), null);

        assertThat(result.getOptionalTags()).hasSize(1);
        assertThat(result.getOptionalTags().get(0).getLabel()).isEqualTo("B");
    }

    @Test
    void toOrder_optionalTagsAreNullWhenInputOptionalTagsAreNull() {
        CreateOrderInput input = new CreateOrderInput(
                Arrays.asList("k"),
                null,
                Arrays.asList(new TagInput("t1", "A")),
                null,
                phoneInputs(),
                null);

        Order result = input.toOrder("o-6", phones(), null);

        assertThat(result.getOptionalTags()).isNull();
    }

    @Test
    void toOrder_passesPhonesThroughAsRequiredParam() {
        CreateOrderInput input = new CreateOrderInput(
                Arrays.asList("k"),
                null,
                Arrays.asList(new TagInput("t1", "A")),
                null,
                phoneInputs(),
                null);

        Order result = input.toOrder("o-7", phones(), null);

        assertThat(result.getPhones()).hasSize(2);
        assertThat(result.getPhones().get(0).getNumber()).isEqualTo("555-1234");
    }

    @Test
    void toOrder_assignsRequiredIdParam() {
        CreateOrderInput input = new CreateOrderInput(
                Arrays.asList("k"),
                null,
                Arrays.asList(new TagInput("t1", "A")),
                null,
                phoneInputs(),
                null);

        Order result = input.toOrder("order-99", phones(), null);

        assertThat(result.getId()).isEqualTo("order-99");
    }

    // -------------------------------------------------------------------------
    // fromOrder
    // -------------------------------------------------------------------------

    @Test
    void fromOrder_copiesKeywordsAndNotes() {
        Order order = new Order("o-8",
                Arrays.asList("x", "y"),
                Arrays.asList("note"),
                Arrays.asList(new Tag("t1", "X")),
                null,
                phones(),
                null);

        CreateOrderInput result = CreateOrderInput.fromOrder(order, phoneInputs(), null);

        assertThat(result.getKeywords()).containsExactly("x", "y");
        assertThat(result.getNotes()).containsExactly("note");
    }

    @Test
    void fromOrder_reverseMapsTags() {
        Order order = new Order("o-9",
                Arrays.asList("k"),
                null,
                Arrays.asList(new Tag("t1", "Promo")),
                null,
                phones(),
                null);

        CreateOrderInput result = CreateOrderInput.fromOrder(order, phoneInputs(), null);

        assertThat(result.getTags()).hasSize(1);
        assertThat(result.getTags().get(0).getId()).isEqualTo("t1");
        assertThat(result.getTags().get(0).getLabel()).isEqualTo("Promo");
    }

    @Test
    void fromOrder_nullableOptionalTagsAreNullWhenOrderHasNone() {
        Order order = new Order("o-10",
                Arrays.asList("k"),
                null,
                Arrays.asList(new Tag("t1", "A")),
                null,
                phones(),
                null);

        CreateOrderInput result = CreateOrderInput.fromOrder(order, phoneInputs(), null);

        assertThat(result.getOptionalTags()).isNull();
    }

    @Test
    void fromOrder_passesUnmappedPhonesParam() {
        Order order = new Order("o-11",
                Arrays.asList("k"),
                null,
                Arrays.asList(new Tag("t1", "A")),
                null,
                phones(),
                null);

        List<PhoneInput> pIn = phoneInputs();
        CreateOrderInput result = CreateOrderInput.fromOrder(order, pIn, null);

        assertThat(result.getPhones()).isSameAs(pIn);
    }
}
