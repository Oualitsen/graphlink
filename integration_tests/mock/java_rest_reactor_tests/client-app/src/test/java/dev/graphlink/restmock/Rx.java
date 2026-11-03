package dev.graphlink.restmock;

import dev.graphlink.restmock.generated.client.RestResponse;
import java.util.function.Supplier;
import reactor.core.publisher.Mono;

final class Rx {
    private Rx() {}

    static <T> T block(Mono<T> signal) { return signal.block(); }

    static Throwable failure(Mono<?> signal) {
        try {
            signal.block();
            return null;
        } catch (Throwable t) {
            return t;
        }
    }

    static <T> Mono<T> just(T value) { return Mono.just(value); }

    static Mono<RestResponse> deferred(Supplier<RestResponse> supplier) { return Mono.fromSupplier(supplier); }
}
