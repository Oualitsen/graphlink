package dev.graphlink.restmock;

import dev.graphlink.restmock.generated.client.RestResponse;
import io.smallrye.mutiny.Uni;
import java.util.function.Supplier;

final class Rx {
    private Rx() {}

    static <T> T block(Uni<T> signal) { return signal.await().indefinitely(); }

    static Throwable failure(Uni<?> signal) {
        try {
            signal.await().indefinitely();
            return null;
        } catch (Throwable t) {
            return t;
        }
    }

    static <T> Uni<T> just(T value) { return Uni.createFrom().item(value); }

    static Uni<RestResponse> deferred(Supplier<RestResponse> supplier) { return Uni.createFrom().<RestResponse>item(supplier); }
}
