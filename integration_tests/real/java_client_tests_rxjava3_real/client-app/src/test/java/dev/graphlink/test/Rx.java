package dev.graphlink.test;

import io.reactivex.rxjava3.core.Observable;
import io.reactivex.rxjava3.core.Single;
import io.reactivex.rxjava3.disposables.Disposable;
import java.util.concurrent.Callable;
import java.util.function.Consumer;

final class Rx {
    private Rx() {}

    static <T> T block(Single<T> signal) { return signal.blockingGet(); }

    static Single<String> deferred(Callable<String> work) { return Single.fromCallable(work); }

    static <T> Runnable subscribe(Observable<T> stream, Consumer<T> onNext) {
        Disposable subscription = stream.subscribe(onNext::accept);
        return subscription::dispose;
    }

    static <T> Runnable subscribe(Observable<T> stream, Consumer<T> onNext, Consumer<Throwable> onError, Runnable onComplete) {
        Disposable subscription = stream.subscribe(onNext::accept, onError::accept, onComplete::run);
        return subscription::dispose;
    }
}
