package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import org.junit.jupiter.api.Test;

import java.util.concurrent.CompletableFuture;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class CacheConcurrencyTest {

    private final GraphLinkClient client = newRealClient();

    private static String freshId() {
        return "java-" + System.nanoTime();
    }

    @Test
    void concurrentRequestsForTwoDifferentKeysMakeTwoCalls() {
        String id = freshId();
        CompletableFuture<Void> a = CompletableFuture.runAsync(() -> client.queries.cachedSlow(id + "-a", 300));
        CompletableFuture<Void> b = CompletableFuture.runAsync(() -> client.queries.cachedSlow(id + "-b", 300));
        CompletableFuture.allOf(a, b).join();
        assertEquals(1, client.queries.cachedSlowCalls(id + "-a").getCachedSlowCalls());
        assertEquals(1, client.queries.cachedSlowCalls(id + "-b").getCachedSlowCalls());
    }

    @Test
    void aResponseInFlightDuringAnInvalidationIsNotStored() throws Exception {
        String id = freshId();
        CompletableFuture<Integer> slow =
                CompletableFuture.supplyAsync(() -> client.queries.cachedSlow(id, 600).getCachedSlow());
        Thread.sleep(150);
        client.mutations.bumpSlow(id);
        assertEquals(0, slow.get());
        assertEquals(1, client.queries.cachedSlow(id, 600).getCachedSlow());
    }
}
