package dev.graphlink.errors;

import io.smallrye.mutiny.Uni;

final class Rx {
    private Rx() {}

    static <T> T block(Uni<T> signal) { return signal.await().indefinitely(); }
}
