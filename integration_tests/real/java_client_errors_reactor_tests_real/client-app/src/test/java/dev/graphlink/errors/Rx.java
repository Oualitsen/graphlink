package dev.graphlink.errors;

import reactor.core.publisher.Mono;

final class Rx {
    private Rx() {}

    static <T> T block(Mono<T> signal) { return signal.block(); }
}
