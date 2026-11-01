package dev.graphlink.test;

import reactor.core.publisher.Mono;

import java.util.function.Supplier;

final class Reactive {
    private Reactive() {}

    static <T> T await(Mono<T> mono) {
        return mono.block();
    }

    static Mono<String> fromSupplier(Supplier<String> supplier) {
        return Mono.fromSupplier(supplier);
    }
}
