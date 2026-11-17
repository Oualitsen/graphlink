package dev.graphlink.rest;

import static dev.graphlink.rest.Support.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.rest.generated.client.*;
import java.util.concurrent.CompletableFuture;
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
}
