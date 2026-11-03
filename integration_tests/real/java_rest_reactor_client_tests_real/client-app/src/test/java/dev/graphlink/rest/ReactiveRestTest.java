package dev.graphlink.rest;

import static dev.graphlink.rest.Support.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.rest.generated.client.*;
import dev.graphlink.rest.generated.inputs.ProductIn;
import dev.graphlink.rest.generated.types.Product;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

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
        Mono<?> pending = counting.queries.count();
        assertEquals(0, calls.get());
        pending.block();
        assertTrue(calls.get() >= 1);
    }

    @Test
    void nullableResultsCompleteEmpty() {
        StepVerifier.create(client.queries.status(204)).verifyComplete();
        StepVerifier.create(client.queries.textOptional()).verifyComplete();
        StepVerifier.create(client.queries.avatarOrEmpty("p1")).verifyComplete();
    }

    @Test
    void nonNullEmptyBodyIsAnErrorSignal() {
        StepVerifier.create(client.queries.statusNonNull(204)).expectError(IllegalStateException.class).verify();
    }

    @Test
    void voidOperationsCompleteWithoutAValue() {
        client.mutations.uploadAvatar("p1", uploadOf(pattern(10))).block();
        StepVerifier.create(client.mutations.deleteProduct("p2")).verifyComplete();
    }

    @Test
    void restErrorsAreErrorSignals() {
        StepVerifier.create(client.queries.status(404))
                .expectErrorSatisfies(e -> {
                    assertInstanceOf(RestError.class, e);
                    assertEquals(404, ((RestError) e).getStatus());
                })
                .verify();
    }

    @Test
    void valuesFlowThrough() {
        StepVerifier.create(client.queries.status(200).map(Product::getName)).expectNext("Pen").verifyComplete();
        StepVerifier.create(client.mutations.createProduct(new ProductIn("Lamp", 3.0, null, null)).map(Product::getName))
                .expectNext("Lamp")
                .verifyComplete();
    }

    @Test
    void cachedCallsServeFromTheStoreWithoutSubscribingTwiceToTheNetwork() {
        assertEquals(1, client.queries.counter("rx").block().getN());
        assertEquals(1, client.queries.counter("rx").block().getN());
    }
}
