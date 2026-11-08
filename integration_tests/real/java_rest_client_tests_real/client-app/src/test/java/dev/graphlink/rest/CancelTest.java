package dev.graphlink.rest;

import static dev.graphlink.rest.Support.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.rest.generated.client.*;
import java.util.concurrent.Callable;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import org.junit.jupiter.api.Test;

class CancelTest {
    private static Callable<Object> call(GraphLinkClient client, char op) {
        if (op == 'g') return () -> client.queries.getCount();
        if (op == 'c') return () -> client.queries.count();
        if (op == 'k') return () -> client.queries.cachedStatus(200);
        return () -> client.queries.status(200);
    }

    @Test
    void aCallThatIsInterruptedReturnsPromptlyAndLeavesTheClientUsable() throws Exception {
        for (char op : "gcpk".toCharArray()) {
            postFault("/_reset");
            GraphLinkClient client = newClient(FAULT_URL);
            postFault("/_arm?fault=slow");
            long started = System.nanoTime();
            CountDownLatch ended = new CountDownLatch(1);
            Future<Object> future = POOL.submit(() -> {
                try {
                    return call(client, op).call();
                } finally {
                    ended.countDown();
                }
            });
            assertThrows(TimeoutException.class, () -> future.get(200, TimeUnit.MILLISECONDS), "op " + op);
            future.cancel(true);
            assertTrue(ended.await(500, TimeUnit.MILLISECONDS), op + ": the interrupted call kept waiting for the server");
            long elapsedMs = (System.nanoTime() - started) / 1_000_000;
            assertTrue(elapsedMs < 900, op + ": waited " + elapsedMs + " ms for a response nobody wanted");
            call(client, op).call();
        }
    }
}
