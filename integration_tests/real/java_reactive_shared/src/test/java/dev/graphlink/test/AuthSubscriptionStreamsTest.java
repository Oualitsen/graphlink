package dev.graphlink.test;

import dev.graphlink.test.generated.client.DefaultGraphLinkClientAdapter;
import dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter;
import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.client.JacksonGraphLinkJsonCodec;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Supplier;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class AuthSubscriptionStreamsTest {

    private static final AtomicInteger NEXT = new AtomicInteger();

    private final List<DefaultGraphLinkWebSocketAdapter> adapters = new ArrayList<>();
    private final List<Runnable> disposers = new CopyOnWriteArrayList<>();

    @AfterEach
    void tearDown() {
        disposers.forEach(Runnable::run);
        adapters.forEach(DefaultGraphLinkWebSocketAdapter::close);
    }

    private GraphLinkClient clientWith(Supplier<Map<String, String>> headers) {
        JacksonGraphLinkJsonCodec codec = new JacksonGraphLinkJsonCodec();
        DefaultGraphLinkWebSocketAdapter ws = new DefaultGraphLinkWebSocketAdapter(WS_URL, headers);
        adapters.add(ws);
        return new GraphLinkClient(new DefaultGraphLinkClientAdapter(SERVER_URL, headers, codec), null, codec, codec, ws);
    }

    private static final class Outcome {
        final List<Integer> ticks = new CopyOnWriteArrayList<>();
        final AtomicReference<Throwable> error = new AtomicReference<>();
        final CountDownLatch ended = new CountDownLatch(1);
    }

    private Outcome secureTicks(GraphLinkClient client, int count) throws InterruptedException {
        Outcome outcome = new Outcome();
        disposers.add(Rx.subscribe(client.subscriptions.secureTicks(count),
                response -> outcome.ticks.add(response.getSecureTicks()),
                e -> { outcome.error.set(e); outcome.ended.countDown(); },
                outcome.ended::countDown));
        assertTrue(outcome.ended.await(10, TimeUnit.SECONDS), "stream never ended");
        return outcome;
    }

    @Test
    void connectionInitCarriesTheToken() throws InterruptedException {
        String token = "java-reactive-" + System.nanoTime() + "-" + NEXT.incrementAndGet();
        Outcome outcome = secureTicks(clientWith(() -> Map.of("Authorization", "Bearer " + token)), 3);
        assertNull(outcome.error.get());
        assertEquals(List.of(1, 2, 3), outcome.ticks);
        assertEquals(1, Rx.block(newRealClient().queries.secureTickStarts(token)).getSecureTickStarts());
    }

    @Test
    void aSubscriptionWithoutATokenFails() throws InterruptedException {
        Outcome outcome = secureTicks(clientWith(null), 3);
        assertTrue(outcome.ticks.isEmpty());
        assertNotNull(outcome.error.get());
    }
}
