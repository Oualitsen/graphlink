package dev.graphlink.rest;

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

}
