package dev.graphlink.test;

import io.reactivex.rxjava3.core.Single;

import java.util.function.Supplier;

final class Reactive {
    private Reactive() {}

    static <T> T await(Single<T> single) {
        return single.blockingGet();
    }

    static Single<String> fromSupplier(Supplier<String> supplier) {
        return Single.fromCallable(supplier::get);
    }
}
