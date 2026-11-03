package dev.graphlink.rest;

import static dev.graphlink.rest.Support.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.rest.generated.client.*;
import dev.graphlink.rest.generated.inputs.ProductIn;
import dev.graphlink.rest.generated.types.Product;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class ReactiveRestTest {
    private GraphLinkClient client;

    @BeforeEach
    void setUp() throws Exception {
        resetServer();
        client = newClient();
    }

    @Test
    void nothingHappensUntilSubscribed() {
        AtomicInteger calls = new AtomicInteger();
        GraphLinkClient counting = newClient(() -> {
            calls.incrementAndGet();
            return java.util.Collections.emptyMap();
        });
        var pending = counting.queries.count();
        assertEquals(0, calls.get());
        Rx.block(pending);
        assertTrue(calls.get() >= 1);
    }

    @Test
    void nullableResultsCompleteEmpty() {
        assertNull(Rx.block(client.queries.status(204)));
        assertNull(Rx.block(client.queries.textOptional()));
        assertNull(Rx.block(client.queries.avatarOrEmpty("p1")));
    }

    @Test
    void nonNullEmptyBodyIsAnErrorSignal() {
        assertInstanceOf(IllegalStateException.class, Rx.failure(client.queries.statusNonNull(204)));
    }

    @Test
    void voidOperationsCompleteWithoutAValue() {
        Rx.block(client.mutations.uploadAvatar("p1", uploadOf(pattern(10))));
        assertNull(Rx.failure(client.mutations.deleteProduct("p2")));
    }

    @Test
    void restErrorsAreErrorSignals() {
        RestError error = assertInstanceOf(RestError.class, Rx.failure(client.queries.status(404)));
        assertEquals(404, error.getStatus());
    }

    @Test
    void valuesFlowThrough() {
        assertEquals("Pen", Rx.block(client.queries.status(200)).getName());
        Product created = Rx.block(client.mutations.createProduct(new ProductIn("Lamp", 3.0, null, null)));
        assertEquals("Lamp", created.getName());
    }

    @Test
    void cachedCallsServeFromTheStoreWithoutSubscribingTwiceToTheNetwork() {
        assertEquals(1, Rx.block(client.queries.counter("rx")).getN());
        assertEquals(1, Rx.block(client.queries.counter("rx")).getN());
    }
}
