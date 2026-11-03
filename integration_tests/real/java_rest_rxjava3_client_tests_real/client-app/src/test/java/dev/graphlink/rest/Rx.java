package dev.graphlink.rest;

import io.reactivex.rxjava3.core.Completable;
import io.reactivex.rxjava3.core.Maybe;
import io.reactivex.rxjava3.core.Single;

final class Rx {
    private Rx() {}

    static <T> T block(Single<T> signal) { return signal.blockingGet(); }

    static <T> T block(Maybe<T> signal) { return signal.blockingGet(); }

    static void block(Completable signal) { signal.blockingAwait(); }

    static Throwable failure(Single<?> signal) {
        try {
            signal.blockingGet();
            return null;
        } catch (Throwable t) {
            return t;
        }
    }

    static Throwable failure(Maybe<?> signal) {
        try {
            signal.blockingGet();
            return null;
        } catch (Throwable t) {
            return t;
        }
    }

    static Throwable failure(Completable signal) {
        try {
            signal.blockingAwait();
            return null;
        } catch (Throwable t) {
            return t;
        }
    }

}
