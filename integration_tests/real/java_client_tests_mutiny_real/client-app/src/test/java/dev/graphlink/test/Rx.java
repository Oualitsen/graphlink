package dev.graphlink.test;

import io.smallrye.mutiny.Multi;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.subscription.Cancellable;
import java.util.concurrent.Callable;
import java.util.function.Consumer;

final class Rx {
    private Rx() {}

    static <T> T block(Uni<T> signal) { return signal.await().indefinitely(); }

    static Uni<String> deferred(Callable<String> work) {
        return Uni.createFrom().emitter(emitter -> {
            try {
                emitter.complete(work.call());
            } catch (Exception e) {
                emitter.fail(e);
            }
        });
    }

    static <T> Runnable subscribe(Multi<T> stream, Consumer<T> onNext) {
        Cancellable subscription = stream.subscribe().with(onNext);
        return subscription::cancel;
    }

    static <T> Runnable subscribe(Multi<T> stream, Consumer<T> onNext, Consumer<Throwable> onError, Runnable onComplete) {
        Cancellable subscription = stream.subscribe().with(onNext, onError, onComplete);
        return subscription::cancel;
    }
}
