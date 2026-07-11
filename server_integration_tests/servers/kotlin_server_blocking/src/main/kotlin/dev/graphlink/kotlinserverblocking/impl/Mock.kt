package dev.graphlink.kotlinserverblocking.impl

import dev.graphlink.kotlinserverblocking.generated.types.Product

/** Deterministic synthesized data for the hoist-args resolvers. */
internal object Mock {
    fun products(prefix: String, count: Int, offset: Int): List<Product> =
        (0 until count).map { i ->
            val n = offset + i
            Product(id = "$prefix-$n", name = "$prefix-$n")
        }
}
