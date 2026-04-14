package com.example;

import com.example.generated.inputs.CartItemInput;
import com.example.generated.inputs.ItemTagInput;
import com.example.generated.types.CartItem;
import com.example.generated.types.ItemTag;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * Case 9 — Nested mapped input list where nested toXxx() requires params.
 * ItemTagInput.labels is nullable → toItemTag(defaultLabels) is required.
 * CartItemInput.tags: toItemTag() has required params → tags promoted to required
 * param in toCartItem(). fromCartItem() takes tags as param too (element mismatch).
 */
class MappingCase9Test {

    // ItemTagInput — toItemTag / fromItemTag

    @Test
    void toItemTag_usesActualLabelsWhenPresent() {
        ItemTagInput input = new ItemTagInput("it-1", Arrays.asList("red", "blue"));
        ItemTag result = input.toItemTag(Collections.emptyList());

        assertThat(result.id()).isEqualTo("it-1");
        assertThat(result.labels()).containsExactly("red", "blue");
    }

    @Test
    void toItemTag_fallsBackToDefaultLabelsWhenNull() {
        ItemTagInput input = new ItemTagInput("it-2", null);
        ItemTag result = input.toItemTag(Arrays.asList("default"));

        assertThat(result.labels()).containsExactly("default");
    }

    @Test
    void toItemTag_withNullLabelsAndEmptyDefault() {
        ItemTagInput input = new ItemTagInput("it-3", null);
        assertThat(input.toItemTag(Collections.emptyList()).labels()).isEmpty();
    }

    @Test
    void fromItemTag_reversesLabels() {
        ItemTag tag = new ItemTag("it-4", Arrays.asList("green", "yellow"));
        ItemTagInput result = ItemTagInput.fromItemTag(tag);

        assertThat(result.id()).isEqualTo("it-4");
        assertThat(result.labels()).containsExactly("green", "yellow");
    }

    // CartItemInput — toCartItem / fromCartItem

    @Test
    void toCartItem_assignsIdAndPassedTags() {
        ItemTagInput rawTag = new ItemTagInput("it-5", Arrays.asList("promo"));
        ItemTag convertedTag = rawTag.toItemTag(Collections.emptyList());

        CartItemInput input = new CartItemInput("ci-1", Arrays.asList(rawTag));
        CartItem result = input.toCartItem(Arrays.asList(convertedTag));

        assertThat(result.id()).isEqualTo("ci-1");
        assertThat(result.tags()).hasSize(1);
        assertThat(result.tags().get(0).id()).isEqualTo("it-5");
        assertThat(result.tags().get(0).labels()).containsExactly("promo");
    }

    @Test
    void toCartItem_acceptsEmptyTagsList() {
        CartItemInput input = new CartItemInput("ci-2", Collections.emptyList());

        assertThatCode(() -> input.toCartItem(Collections.emptyList())).doesNotThrowAnyException();
    }

    @Test
    void fromCartItem_passesTagsParamThrough() {
        CartItem cartItem = new CartItem("ci-3", Arrays.asList(new ItemTag("it-6", Arrays.asList("x"))));
        List<ItemTagInput> tagsParam = Arrays.asList(new ItemTagInput("it-6", Arrays.asList("x")));

        CartItemInput result = CartItemInput.fromCartItem(cartItem, tagsParam);

        assertThat(result.id()).isEqualTo("ci-3");
        assertThat(result.tags()).isSameAs(tagsParam);
    }

    @Test
    void fromCartItem_withNullLabelsInTagsParamDoesNotThrow() {
        CartItem cartItem = new CartItem("ci-4", Arrays.asList(new ItemTag("it-7", Arrays.asList("y"))));
        List<ItemTagInput> tagsParam = Arrays.asList(new ItemTagInput("it-7", null));

        assertThatCode(() -> CartItemInput.fromCartItem(cartItem, tagsParam)).doesNotThrowAnyException();
    }

    @Test
    void roundTrip_itemTag_defaultLabelsPreserved() {
        ItemTagInput original = new ItemTagInput("it-8", null);
        ItemTag converted = original.toItemTag(Arrays.asList("fallback"));
        ItemTagInput roundTrip = ItemTagInput.fromItemTag(converted);

        assertThat(roundTrip.id()).isEqualTo("it-8");
        // fromItemTag copies labels from ItemTag → ["fallback"]
        assertThat(roundTrip.labels()).containsExactly("fallback");
    }
}
