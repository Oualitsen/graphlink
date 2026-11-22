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

}
