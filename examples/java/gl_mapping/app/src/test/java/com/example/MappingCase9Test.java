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
 * Case 9 — Nested mapped input list where the nested toXxx() requires params.
 *
 * ItemTagInput @glMapsTo(type: "ItemTag")
 *   id: ID!
 *   labels: [String!]   ← nullable → non-null in ItemTag → toItemTag(defaultLabels)
 *
 * CartItemInput @glMapsTo(type: "CartItem")
 *   id: ID!
 *   tags: [ItemTagInput!]!  ← toItemTag() has required params → tags becomes a
 *                              required param in toCartItem(List<ItemTag> tags).
 *                              fromCartItem() still takes tags as a param because
 *                              of the element nullability mismatch.
 */
class MappingCase9Test {

    // -------------------------------------------------------------------------
    // ItemTagInput — toItemTag / fromItemTag
    // -------------------------------------------------------------------------

    @Test
    void toItemTag_usesActualLabelsWhenPresent() {
        ItemTagInput input = new ItemTagInput("it-1", Arrays.asList("red", "blue"));
        ItemTag result = input.toItemTag(Collections.emptyList());

        assertThat(result.getId()).isEqualTo("it-1");
        assertThat(result.getLabels()).containsExactly("red", "blue");
    }

    @Test
    void toItemTag_fallsBackToDefaultLabelsWhenNull() {
        ItemTagInput input = new ItemTagInput("it-2", null);
        ItemTag result = input.toItemTag(Arrays.asList("default"));

        assertThat(result.getLabels()).containsExactly("default");
    }

    @Test
    void toItemTag_withNullLabelsAndEmptyDefault() {
        ItemTagInput input = new ItemTagInput("it-3", null);
        ItemTag result = input.toItemTag(Collections.emptyList());

        assertThat(result.getLabels()).isEmpty();
    }

    @Test
    void fromItemTag_reversesLabels() {
        ItemTag tag = new ItemTag("it-4", Arrays.asList("green", "yellow"));
        ItemTagInput result = ItemTagInput.fromItemTag(tag);

        assertThat(result.getId()).isEqualTo("it-4");
        assertThat(result.getLabels()).containsExactly("green", "yellow");
    }

    // -------------------------------------------------------------------------
    // CartItemInput — toCartItem / fromCartItem
    // tags is a required param because toItemTag() itself requires params.
    // -------------------------------------------------------------------------

    @Test
    void toCartItem_assignsIdAndPassedTags() {
        // Pre-convert tags using toItemTag() before calling toCartItem()
        ItemTagInput rawTag = new ItemTagInput("it-5", Arrays.asList("promo"));
        ItemTag convertedTag = rawTag.toItemTag(Collections.emptyList());

        CartItemInput input = new CartItemInput("ci-1", Arrays.asList(rawTag));
        CartItem result = input.toCartItem(Arrays.asList(convertedTag));

        assertThat(result.getId()).isEqualTo("ci-1");
        assertThat(result.getTags()).hasSize(1);
        assertThat(result.getTags().get(0).getId()).isEqualTo("it-5");
        assertThat(result.getTags().get(0).getLabels()).containsExactly("promo");
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

        assertThat(result.getId()).isEqualTo("ci-3");
        assertThat(result.getTags()).isSameAs(tagsParam);
    }

    @Test
    void fromCartItem_withNullLabelsInTagsParamDoesNotThrow() {
        CartItem cartItem = new CartItem("ci-4", Arrays.asList(new ItemTag("it-7", Arrays.asList("y"))));
        List<ItemTagInput> tagsParam = Arrays.asList(new ItemTagInput("it-7", null)); // nullable labels

        assertThatCode(() -> CartItemInput.fromCartItem(cartItem, tagsParam)).doesNotThrowAnyException();
    }

    @Test
    void roundTrip_itemTag_withNullLabels() {
        ItemTagInput original = new ItemTagInput("it-8", null);
        ItemTag converted = original.toItemTag(Arrays.asList("fallback"));
        ItemTagInput roundTrip = ItemTagInput.fromItemTag(converted);

        assertThat(roundTrip.getId()).isEqualTo("it-8");
        // fromItemTag copies the non-null labels from ItemTag → roundTrip has ["fallback"]
        assertThat(roundTrip.getLabels()).containsExactly("fallback");
    }
}
