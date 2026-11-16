package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.concurrent.atomic.AtomicInteger;

import static dev.graphlink.test.Fixtures.newRealClient;
import static org.junit.jupiter.api.Assertions.*;

/** The server fails the first cachedFlaky / cachedFlakyNullable call per id and counts every call. */
class CacheErrorsTest {

    private static final AtomicInteger NEXT = new AtomicInteger();

    private GraphLinkClient client;
    private String id;

    @BeforeEach
    void setUp() {
        client = newRealClient();
        id = "java-" + System.nanoTime() + "-" + NEXT.incrementAndGet();
    }

    private int serverCalls() {
        return client.queries.cachedFlakyCalls(id).getCachedFlakyCalls();
    }

    @Test
    void aFailedResponseIsNotCached() {
        assertThrows(RuntimeException.class, () -> client.queries.cachedFlaky(id));
        assertEquals(1, serverCalls());

        assertEquals("user-1", client.queries.cachedFlaky(id).getCachedFlaky().getId());
        assertEquals(2, serverCalls());

        assertEquals("user-1", client.queries.cachedFlaky(id).getCachedFlaky().getId());
        assertEquals(2, serverCalls());
    }

    @Test
    void aPartialFailureIsNotCached() {
        assertThrows(RuntimeException.class, () -> client.queries.cachedFlakyNullable(id));
        assertEquals(1, serverCalls());

        assertEquals("user-1", client.queries.cachedFlakyNullable(id).getCachedFlakyNullable().getId());
        assertEquals(2, serverCalls());

        assertEquals("user-1", client.queries.cachedFlakyNullable(id).getCachedFlakyNullable().getId());
        assertEquals(2, serverCalls());
    }
}
