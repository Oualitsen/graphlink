package dev.graphlink.test;

import dev.graphlink.test.generated.client.DefaultGraphLinkClientAdapter;
import dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter;
import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.client.GraphLinkException;
import dev.graphlink.test.generated.client.GraphLinkSubscriptionListener;
import dev.graphlink.test.generated.client.JacksonGraphLinkJsonCodec;
import dev.graphlink.test.generated.types.LabelTicksResponse;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BooleanSupplier;
import java.util.function.Supplier;

import static dev.graphlink.test.SubscriptionReconnectTest.*;
import static org.junit.jupiter.api.Assertions.*;

@Timeout(value = 3, unit = TimeUnit.MINUTES)
class SubscriptionReconnectCasesTest {

    private static final int PORT = 9934;

    private static final class Stream implements GraphLinkSubscriptionListener<LabelTicksResponse> {
        final List<String> events = new CopyOnWriteArrayList<>();
        final AtomicReference<GraphLinkException> error = new AtomicReference<>();
        final AtomicBoolean completed = new AtomicBoolean();

        @Override public void onMessage(LabelTicksResponse response) { events.add(response.getLabelTicks()); }
        @Override public void onComplete() { completed.set(true); }
        @Override public void onError(GraphLinkException e) { error.set(e); }

        void awaitEvent(String label) throws InterruptedException {
            int seen = events.size();
            until("an event for " + label + " after the restart",
                    () -> events.subList(seen, events.size()).stream().anyMatch(e -> e.startsWith(label + "-")));
        }
    }

    private DefaultGraphLinkWebSocketAdapter ws;
    private GraphLinkClient client;

    @BeforeEach
    void setUp() throws Exception {
        killPort(PORT);
        startServer(PORT);
    }

    @AfterEach
    void tearDown() throws Exception {
        if (ws != null) ws.close();
        killPort(PORT);
    }

    private static void until(String what, BooleanSupplier check) throws InterruptedException {
        long deadline = System.currentTimeMillis() + 60_000;
        while (!check.getAsBoolean()) {
            assertTrue(System.currentTimeMillis() < deadline, "timed out: " + what);
            Thread.sleep(200);
        }
    }

    private void connect(Supplier<Map<String, String>> headers, Integer maxAttempts, long maxDelayMs) {
        JacksonGraphLinkJsonCodec codec = new JacksonGraphLinkJsonCodec();
        ws = new DefaultGraphLinkWebSocketAdapter(wsUrl(PORT), headers, maxAttempts, maxDelayMs);
        client = new GraphLinkClient(new DefaultGraphLinkClientAdapter(httpUrl(PORT), codec), null, codec, codec, ws);
    }

    private Stream subscribe(String label, int count) {
        Stream stream = new Stream();
        client.subscriptions.labelTicks(label, count, stream);
        return stream;
    }

    private int starts(String label) {
        return client.queries.labelTickStarts(label).getLabelTickStarts();
    }

    private void restart() throws Exception {
        killPort(PORT);
        startServer(PORT);
    }

    @Test
    void resubscribesWithTheSameVariables() throws Exception {
        connect(null, 10, 30_000);
        Stream bob = subscribe("bob", 1000);
        until("first event", () -> !bob.events.isEmpty());
        assertEquals("bob-1", bob.events.get(0));

        restart();
        bob.awaitEvent("bob");
        assertEquals(1, starts("bob"));
    }

    @Test
    void doesNotResubscribeACompletedSubscription() throws Exception {
        connect(null, 10, 30_000);
        Stream done = subscribe("done", 2);
        until("completion", done.completed::get);
        assertEquals(2, done.events.size());

        restart();
        Thread.sleep(6000);
        assertEquals(0, starts("done"));
        assertEquals(2, done.events.size());
    }

    @Test
    void resumesEveryOpenSubscriptionOnOneSocket() throws Exception {
        connect(null, 10, 30_000);
        Stream a = subscribe("a", 1000);
        Stream b = subscribe("b", 1000);
        until("first events", () -> !a.events.isEmpty() && !b.events.isEmpty());

        restart();
        a.awaitEvent("a");
        b.awaitEvent("b");
        assertEquals(1, starts("a"));
        assertEquals(1, starts("b"));
    }

    @Test
    void aRestartDuringConnectionInitSubscribesOnce() throws Exception {
        connect(() -> Map.of("Ack-Delay", "3000"), 10, 30_000);
        Stream init = subscribe("init", 1000);
        Thread.sleep(1000);

        restart();
        init.awaitEvent("init");
        Thread.sleep(2000);
        assertEquals(1, starts("init"));
    }

    @Test
    void givesUpWithAVisibleError() throws Exception {
        connect(null, 2, 1000);
        Stream giveUp = subscribe("giveup", 1000);
        until("first event", () -> !giveUp.events.isEmpty());
        killPort(PORT);

        until("an error or an end after the reconnect attempts ran out",
                () -> giveUp.error.get() != null || giveUp.completed.get());
        assertNotNull(giveUp.error.get());
    }
}
