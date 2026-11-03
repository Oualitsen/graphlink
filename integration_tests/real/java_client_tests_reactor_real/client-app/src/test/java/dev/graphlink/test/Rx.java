package dev.graphlink.test;

import java.util.concurrent.Callable;
import java.util.function.Consumer;
import reactor.core.Disposable;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

final class Rx {
    private Rx() {}

    static <T> T block(Mono<T> signal) { return signal.block(); }

    static Mono<String> deferred(Callable<String> work) { return Mono.fromCallable(work); }

    static <T> Runnable subscribe(Flux<T> stream, Consumer<T> onNext) {
        Disposable subscription = stream.subscribe(onNext);
        return subscription::dispose;
    }

    static <T> Runnable subscribe(Flux<T> stream, Consumer<T> onNext, Consumer<Throwable> onError, Runnable onComplete) {
        Disposable subscription = stream.subscribe(onNext, onError, onComplete);
        return subscription::dispose;
    }
}
