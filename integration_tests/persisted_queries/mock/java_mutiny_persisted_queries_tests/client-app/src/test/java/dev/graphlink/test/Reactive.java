package dev.graphlink.test;

import io.smallrye.mutiny.Uni;

import java.util.function.Supplier;

final class Reactive {
    private Reactive() {}

    static <T> T await(Uni<T> uni) {
        return uni.await().indefinitely();
    }

    static Uni<String> fromSupplier(Supplier<String> supplier) {
        return Uni.createFrom().item(supplier);
    }
}
