package dev.graphlink.test;

import dev.graphlink.test.generated.client.DefaultGraphLinkClientAdapter;
import dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter;
import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.client.GraphLinkException;
import dev.graphlink.test.generated.client.GraphLinkSubscriptionListener;
import dev.graphlink.test.generated.client.JacksonGraphLinkJsonCodec;
import dev.graphlink.test.generated.types.SecureTicksResponse;
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

class AuthTest {

    private static final AtomicInteger NEXT = new AtomicInteger();

    private final List<DefaultGraphLinkWebSocketAdapter> adapters = new ArrayList<>();

    @AfterEach
    void tearDown() {
        adapters.forEach(DefaultGraphLinkWebSocketAdapter::close);
    }

    private GraphLinkClient clientWith(Supplier<Map<String, String>> headers) {
        JacksonGraphLinkJsonCodec codec = new JacksonGraphLinkJsonCodec();
        DefaultGraphLinkWebSocketAdapter ws = new DefaultGraphLinkWebSocketAdapter(WS_URL, headers);
        adapters.add(ws);
        return new GraphLinkClient(new DefaultGraphLinkClientAdapter(SERVER_URL, headers, codec), null, codec, codec, ws);
    }

    private static final class Outcome implements GraphLinkSubscriptionListener<SecureTicksResponse> {
        final List<Integer> ticks = new CopyOnWriteArrayList<>();
        final AtomicReference<GraphLinkException> error = new AtomicReference<>();
        final CountDownLatch ended = new CountDownLatch(1);

        @Override public void onMessage(SecureTicksResponse response) { ticks.add(response.getSecureTicks()); }
        @Override public void onComplete() { ended.countDown(); }
        @Override public void onError(GraphLinkException e) { error.set(e); ended.countDown(); }
    }

    private Outcome secureTicks(GraphLinkClient client, int count) throws InterruptedException {
        Outcome outcome = new Outcome();
        client.subscriptions.secureTicks(count, outcome);
        assertTrue(outcome.ended.await(10, TimeUnit.SECONDS), "stream never ended");
        return outcome;
    }

    @Test
    void headersProviderValuesReachTheServer() {
        GraphLinkClient client = clientWith(() -> Map.of("X-Test", "v1"));
        assertEquals("v1", client.queries.echoHeader("X-Test").getEchoHeader());
        assertNull(client.queries.echoHeader("X-Other").getEchoHeader());
    }

    @Test
    void headersProviderIsEvaluatedOnEveryRequest() {
        AtomicReference<String> token = new AtomicReference<>("first");
        GraphLinkClient client = clientWith(() -> Map.of("Authorization", "Bearer " + token.get()));
        assertEquals("first", client.queries.whoAmI().getWhoAmI());
        token.set("second");
        assertEquals("second", client.queries.whoAmI().getWhoAmI());
    }

    @Test
    void aMissingTokenIsAGraphLinkException() {
        GraphLinkException e = assertThrows(GraphLinkException.class, () -> newRealClient().queries.whoAmI());
        assertFalse(e.getErrors().isEmpty());
    }

    @Test
    void connectionInitCarriesTheToken() throws InterruptedException {
        String token = "java-" + System.nanoTime() + "-" + NEXT.incrementAndGet();
        Outcome outcome = secureTicks(clientWith(() -> Map.of("Authorization", "Bearer " + token)), 3);
        assertNull(outcome.error.get());
        assertEquals(List.of(1, 2, 3), outcome.ticks);
        assertEquals(1, newRealClient().queries.secureTickStarts(token).getSecureTickStarts());
    }

    @Test
    void aSubscriptionWithoutATokenFails() throws InterruptedException {
        Outcome outcome = secureTicks(clientWith(null), 3);
        assertTrue(outcome.ticks.isEmpty());
        assertNotNull(outcome.error.get());
    }
}
