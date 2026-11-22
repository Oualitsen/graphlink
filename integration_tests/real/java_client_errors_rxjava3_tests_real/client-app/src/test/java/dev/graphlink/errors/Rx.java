package dev.graphlink.errors;

import io.reactivex.rxjava3.core.Single;

final class Rx {
    private Rx() {}

    static <T> T block(Single<T> signal) { return signal.blockingGet(); }
}
