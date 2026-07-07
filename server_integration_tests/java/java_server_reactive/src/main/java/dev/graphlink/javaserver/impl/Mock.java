package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.types.Product;

import java.util.ArrayList;
import java.util.List;

/** Deterministic synthesized data for the hoist-args resolvers. */
final class Mock {
    private Mock() {}

    static List<Product> products(String prefix, int count, int offset) {
        List<Product> list = new ArrayList<>();
        for (int i = 0; i < count; i++) {
            int n = offset + i;
            list.add(Product.builder().id(prefix + "-" + n).name(prefix + "-" + n).build());
        }
        return list;
    }
}
