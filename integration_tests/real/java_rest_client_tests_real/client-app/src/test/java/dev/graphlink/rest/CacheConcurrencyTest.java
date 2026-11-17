package dev.graphlink.rest;

import static dev.graphlink.rest.Support.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.rest.generated.client.*;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicBoolean;
import org.junit.jupiter.api.Test;

class CacheConcurrencyTest {

    private final GraphLinkClient client = newClient();

    private static String freshName() {
        return "java-" + System.nanoTime();
    }

    @Test
    void concurrentRequestsForTwoDifferentKeysMakeTwoCalls() {
        String name = freshName();
        CompletableFuture<Void> a = CompletableFuture.runAsync(() -> client.queries.counterSlow(name + "-a", 300), POOL);
        CompletableFuture<Void> b = CompletableFuture.runAsync(() -> client.queries.counterSlow(name + "-b", 300), POOL);
        CompletableFuture.allOf(a, b).join();
        assertEquals(1, client.queries.counterCalls(name + "-a").getN());
        assertEquals(1, client.queries.counterCalls(name + "-b").getN());
    }

    @Test
    void concurrentRequestsForTheSameKeyShareOneCall() {
        String name = freshName();
        CompletableFuture<Void> a = CompletableFuture.runAsync(() -> client.queries.counterSlow(name, 300), POOL);
        CompletableFuture<Void> b = CompletableFuture.runAsync(() -> client.queries.counterSlow(name, 300), POOL);
        CompletableFuture<Void> c = CompletableFuture.runAsync(() -> client.queries.counterSlow(name, 300), POOL);
        CompletableFuture.allOf(a, b, c).join();
        assertEquals(1, client.queries.counterCalls(name).getN());
    }

    @Test
    void aResponseInFlightDuringAnInvalidationIsNotStored() throws Exception {
        String name = freshName();
        CompletableFuture<Integer> slow =
                CompletableFuture.supplyAsync(() -> client.queries.counterSlow(name, 600).getN(), POOL);
        Thread.sleep(150);
        client.mutations.touchSlow(name);
        assertEquals(1, slow.get());
        assertEquals(2, client.queries.counterSlow(name, 600).getN());
    }

    private static final class PausingStore implements GraphLinkCacheStore {
        private final InMemoryGraphLinkCacheStore inner = new InMemoryGraphLinkCacheStore();
        final CountDownLatch reached = new CountDownLatch(1);
        final CountDownLatch release = new CountDownLatch(1);
        private final AtomicBoolean paused = new AtomicBoolean();

        @Override
        public void set(String key, String value) {
            if (!key.startsWith("__tag__") && paused.compareAndSet(false, true)) {
                reached.countDown();
                try {
                    release.await();
                } catch (InterruptedException e) {
                    throw new RuntimeException(e);
                }
            }
            inner.set(key, value);
        }

        @Override
        public String get(String key) {
            return inner.get(key);
        }

        @Override
        public void invalidate(String key) {
            inner.invalidate(key);
        }

        @Override
        public void invalidateAll() {
            inner.invalidateAll();
        }
    }

    @Test
    void anInvalidationThatArrivesWhileTheResponseIsBeingStoredRemovesIt() throws Exception {
        String name = freshName();
        PausingStore store = new PausingStore();
        GraphLinkClient pausing = newClient(store);
        CompletableFuture<Integer> first =
                CompletableFuture.supplyAsync(() -> pausing.queries.counterSlow(name, 50).getN(), POOL);
        store.reached.await();
        CompletableFuture<Void> touch = CompletableFuture.runAsync(() -> pausing.mutations.touchSlow(name), POOL);
        Thread.sleep(300);
        store.release.countDown();
        first.get();
        touch.get();
        assertEquals(2, pausing.queries.counterSlow(name, 50).getN());
    }
}
