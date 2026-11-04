package dev.graphlink.restmock;

import dev.graphlink.restmock.generated.client.RestResponse;
import io.reactivex.rxjava3.core.Completable;
import io.reactivex.rxjava3.core.Maybe;
import io.reactivex.rxjava3.core.Single;
import java.util.function.Supplier;

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

    static <T> Single<T> just(T value) { return Single.just(value); }

    static Single<RestResponse> deferred(Supplier<RestResponse> supplier) { return Single.fromCallable(supplier::get); }
}
