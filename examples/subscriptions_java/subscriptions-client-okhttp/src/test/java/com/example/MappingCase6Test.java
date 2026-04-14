package com.example;

import com.example.generated.inputs.CreateOrderInput;
import com.example.generated.inputs.PhoneInput;
import com.example.generated.inputs.TagInput;
import com.example.generated.types.Order;
import com.example.generated.types.Phone;
import com.example.generated.types.Tag;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * Case 6 — Lists.
 * keywords [String!]! → direct copy; notes [String!] → nullable copy;
 * tags [TagInput!]! → stream map; optionalTags [TagInput!] → null-guarded stream map;
 * phones/optionalPhones → unmapped, required params; id → required param.
 */
class MappingCase6Test {

    private static List<PhoneInput> phoneInputs() {
        return Arrays.asList(new PhoneInput("555-1234", "1"), new PhoneInput("555-5678", "44"));
    }

    private static List<Phone> phones() {
        return Arrays.asList(new Phone("555-1234", "1"), new Phone("555-5678", "44"));
    }

    @Test
    void toOrder_copiesKeywordsDirectly() {
        CreateOrderInput input = new CreateOrderInput(
                Arrays.asList("alpha", "beta"), null,
                Arrays.asList(new TagInput("t1", "Sale")), null,
                phoneInputs(), null);

        Order result = input.toOrder("o-1", phones(), null);

        assertThat(result.keywords()).containsExactly("alpha", "beta");
    }

    @Test
    void toOrder_copiesNullableNotesWhenPresent() {
        CreateOrderInput input = new CreateOrderInput(
                Arrays.asList("k"), Arrays.asList("note1"),
                Arrays.asList(new TagInput("t1", "Sale")), null,
                phoneInputs(), null);

        assertThat(input.toOrder("o-2", phones(), null).notes()).containsExactly("note1");
    }

    @Test
    void toOrder_notesAreNullWhenInputNotesAreNull() {
        CreateOrderInput input = new CreateOrderInput(
                Arrays.asList("k"), null,
                Arrays.asList(new TagInput("t1", "Sale")), null,
                phoneInputs(), null);

        assertThat(input.toOrder("o-3", phones(), null).notes()).isNull();
    }

    @Test
    void toOrder_mapsMappedTagsViaStream() {
        CreateOrderInput input = new CreateOrderInput(
                Arrays.asList("k"), null,
                Arrays.asList(new TagInput("t1", "Flash"), new TagInput("t2", "Promo")), null,
                phoneInputs(), null);

        Order result = input.toOrder("o-4", phones(), null);

        assertThat(result.tags()).hasSize(2);
        assertThat(result.tags().get(0).id()).isEqualTo("t1");
        assertThat(result.tags().get(0).label()).isEqualTo("Flash");
        assertThat(result.tags().get(1).id()).isEqualTo("t2");
    }

    @Test
    void toOrder_mapsNullableOptionalTagsWhenPresent() {
        CreateOrderInput input = new CreateOrderInput(
                Arrays.asList("k"), null,
                Arrays.asList(new TagInput("t1", "A")),
                Arrays.asList(new TagInput("t2", "B")),
                phoneInputs(), null);

        Order result = input.toOrder("o-5", phones(), null);

        assertThat(result.optionalTags()).hasSize(1);
        assertThat(result.optionalTags().get(0).label()).isEqualTo("B");
    }

    @Test
    void toOrder_optionalTagsAreNullWhenInputOptionalTagsAreNull() {
        CreateOrderInput input = new CreateOrderInput(
                Arrays.asList("k"), null,
                Arrays.asList(new TagInput("t1", "A")), null,
                phoneInputs(), null);

        assertThat(input.toOrder("o-6", phones(), null).optionalTags()).isNull();
    }

    @Test
    void toOrder_passesPhonesThroughAsRequiredParam() {
        CreateOrderInput input = new CreateOrderInput(
                Arrays.asList("k"), null,
                Arrays.asList(new TagInput("t1", "A")), null,
                phoneInputs(), null);

        Order result = input.toOrder("o-7", phones(), null);

        assertThat(result.phones()).hasSize(2);
        assertThat(result.phones().get(0).number()).isEqualTo("555-1234");
    }

    @Test
    void toOrder_assignsRequiredIdParam() {
        CreateOrderInput input = new CreateOrderInput(
                Arrays.asList("k"), null,
                Arrays.asList(new TagInput("t1", "A")), null,
                phoneInputs(), null);

        assertThat(input.toOrder("order-99", phones(), null).id()).isEqualTo("order-99");
    }

    @Test
    void fromOrder_copiesKeywordsAndNotes() {
        Order order = new Order("o-8",
                Arrays.asList("x", "y"), Arrays.asList("note"),
                Arrays.asList(new Tag("t1", "X")), null,
                phones(), null);

        CreateOrderInput result = CreateOrderInput.fromOrder(order, phoneInputs(), null);

        assertThat(result.keywords()).containsExactly("x", "y");
        assertThat(result.notes()).containsExactly("note");
    }

    @Test
    void fromOrder_reverseMapsTags() {
        Order order = new Order("o-9",
                Arrays.asList("k"), null,
                Arrays.asList(new Tag("t1", "Promo")), null,
                phones(), null);

        CreateOrderInput result = CreateOrderInput.fromOrder(order, phoneInputs(), null);

        assertThat(result.tags()).hasSize(1);
        assertThat(result.tags().get(0).id()).isEqualTo("t1");
        assertThat(result.tags().get(0).label()).isEqualTo("Promo");
    }

    @Test
    void fromOrder_nullableOptionalTagsAreNullWhenOrderHasNone() {
        Order order = new Order("o-10",
                Arrays.asList("k"), null,
                Arrays.asList(new Tag("t1", "A")), null,
                phones(), null);

        assertThat(CreateOrderInput.fromOrder(order, phoneInputs(), null).optionalTags()).isNull();
    }

    @Test
    void fromOrder_passesUnmappedPhonesParam() {
        Order order = new Order("o-11",
                Arrays.asList("k"), null,
                Arrays.asList(new Tag("t1", "A")), null,
                phones(), null);

        List<PhoneInput> pIn = phoneInputs();
        assertThat(CreateOrderInput.fromOrder(order, pIn, null).phones()).isSameAs(pIn);
    }
}
