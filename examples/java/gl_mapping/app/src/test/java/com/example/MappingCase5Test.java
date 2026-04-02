package com.example;

import com.example.generated.inputs.CreateProductInput;
import com.example.generated.types.Product;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.*;

/**
 * Case 5 — Mix: alias + nullability mismatch + missing field + input-only field.
 * schema: CreateProductInput @glMapsTo(type: "Product")
 *   name: String!   @glMapField(to: "title")
 *   price: Int!     @glMapField(to: "priceInCents")
 *   stock: Int      ← nullable → non-null in Product → defaultStock param
 *   catId: ID!      @glMapField(to: "categoryId")
 *   internalNote: String  ← input-only
 *   # id missing → required param
 */
class MappingCase5Test {

    @Test
    void toProduct_mapsAliasedFields() {
        CreateProductInput input = new CreateProductInput("Widget", 999, 10, "cat-1", null);
        Product result = input.toProduct("p-1", 0);

        assertThat(result.getTitle()).isEqualTo("Widget");        // name → title
        assertThat(result.getPriceInCents()).isEqualTo(999);      // price → priceInCents
        assertThat(result.getCategoryId()).isEqualTo("cat-1");    // catId → categoryId
    }

    @Test
    void toProduct_usesActualStockWhenPresent() {
        CreateProductInput input = new CreateProductInput("Gadget", 500, 42, "cat-2", null);
        Product result = input.toProduct("p-2", 0);

        assertThat(result.getStock()).isEqualTo(42);
    }

    @Test
    void toProduct_fallsBackToDefaultStockWhenNull() {
        CreateProductInput input = new CreateProductInput("Thingamajig", 100, null, "cat-3", null);
        Product result = input.toProduct("p-3", 5);

        assertThat(result.getStock()).isEqualTo(5); // null stock → use default
    }

    @Test
    void toProduct_withNullStock_doesNotThrow() {
        CreateProductInput input = new CreateProductInput("X", 1, null, "cat-4", null);

        assertThatCode(() -> input.toProduct("p-4", 1)).doesNotThrowAnyException();
    }

    @Test
    void toProduct_assignsRequiredIdParam() {
        CreateProductInput input = new CreateProductInput("Y", 200, 3, "cat-5", null);
        Product result = input.toProduct("product-99", 0);

        assertThat(result.getId()).isEqualTo("product-99");
    }

    @Test
    void fromProduct_reversesAliases() {
        Product product = new Product("p-5", "Doohickey", 750, 8, "cat-6");
        CreateProductInput result = CreateProductInput.fromProduct(product, "internal");

        assertThat(result.getName()).isEqualTo("Doohickey");    // title → name
        assertThat(result.getPrice()).isEqualTo(750);           // priceInCents → price
        assertThat(result.getCatId()).isEqualTo("cat-6");       // categoryId → catId
        assertThat(result.getStock()).isEqualTo(8);
    }

    @Test
    void fromProduct_passesInputOnlyNoteAsParam() {
        Product product = new Product("p-6", "Gizmo", 300, 1, "cat-7");
        CreateProductInput result = CreateProductInput.fromProduct(product, "for internal use");

        assertThat(result.getInternalNote()).isEqualTo("for internal use");
    }

    @Test
    void fromProduct_allowsNullInputOnlyNote() {
        Product product = new Product("p-7", "Knick-knack", 50, 100, "cat-8");

        assertThatCode(() -> CreateProductInput.fromProduct(product, null)).doesNotThrowAnyException();
    }
}
