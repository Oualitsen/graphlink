package dev.graphlink.rest;

import io.smallrye.mutiny.Uni;

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

}
