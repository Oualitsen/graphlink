package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import org.junit.jupiter.api.Test;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class CacheConcurrencyTest {

    private static final ExecutorService POOL = Executors.newCachedThreadPool(r -> {
        Thread t = new Thread(r);
        t.setDaemon(true);
        return t;
    });

    private final GraphLinkClient client = newRealClient();

    private static String freshId() {
        return "java-" + System.nanoTime();
    }

    @Test
    void concurrentRequestsForTwoDifferentKeysMakeTwoCalls() {
        String id = freshId();
        CompletableFuture<Void> a = CompletableFuture.runAsync(() -> client.queries.cachedSlow(id + "-a", 300), POOL);
        CompletableFuture<Void> b = CompletableFuture.runAsync(() -> client.queries.cachedSlow(id + "-b", 300), POOL);
        CompletableFuture.allOf(a, b).join();
        assertEquals(1, client.queries.cachedSlowCalls(id + "-a").getCachedSlowCalls());
        assertEquals(1, client.queries.cachedSlowCalls(id + "-b").getCachedSlowCalls());
    }

    @Test
    void concurrentRequestsForTheSameKeyShareOneCall() {
        String id = freshId();
        CompletableFuture<Void> a = CompletableFuture.runAsync(() -> client.queries.cachedSlow(id, 300), POOL);
        CompletableFuture<Void> b = CompletableFuture.runAsync(() -> client.queries.cachedSlow(id, 300), POOL);
        CompletableFuture<Void> c = CompletableFuture.runAsync(() -> client.queries.cachedSlow(id, 300), POOL);
        CompletableFuture.allOf(a, b, c).join();
        assertEquals(1, client.queries.cachedSlowCalls(id).getCachedSlowCalls());
    }

    @Test
    void aResponseInFlightDuringAnInvalidationIsNotStored() throws Exception {
        String id = freshId();
        CompletableFuture<Integer> slow =
                CompletableFuture.supplyAsync(() -> client.queries.cachedSlow(id, 600).getCachedSlow(), POOL);
        long deadline = System.currentTimeMillis() + 10_000;
        while (client.queries.cachedSlowCalls(id).getCachedSlowCalls() == 0) {
            assertTrue(System.currentTimeMillis() < deadline, "the slow call never reached the server");
            Thread.sleep(20);
        }
        client.mutations.bumpSlow(id);
        assertEquals(0, slow.get());
        assertEquals(1, client.queries.cachedSlow(id, 600).getCachedSlow());
    }
}
