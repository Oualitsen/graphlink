package dev.graphlink.test;

import dev.graphlink.test.generated.client.DefaultGraphLinkClientAdapter;
import dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter;
import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.client.JacksonGraphLinkJsonCodec;
import dev.graphlink.test.generated.enums.OnlyOne;
import dev.graphlink.test.generated.enums.Spelling;
import dev.graphlink.test.generated.inputs.ListsInput;
import dev.graphlink.test.generated.types.*;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class SubscriptionStreamsTest {

    private DefaultGraphLinkWebSocketAdapter wsAdapter;
    private GraphLinkClient client;
    private final List<Runnable> disposers = new CopyOnWriteArrayList<>();

    @BeforeEach
    void setUp() {
        JacksonGraphLinkJsonCodec codec = new JacksonGraphLinkJsonCodec();
        wsAdapter = new DefaultGraphLinkWebSocketAdapter(WS_URL);
        client = new GraphLinkClient(new DefaultGraphLinkClientAdapter(SERVER_URL), null, codec, codec, wsAdapter);
    }

    @AfterEach
    void tearDown() {
        disposers.forEach(Runnable::run);
        wsAdapter.close();
    }

    private static final class Outcome<T> {
        final List<T> events = new CopyOnWriteArrayList<>();
        final AtomicReference<Throwable> error = new AtomicReference<>();
        final CountDownLatch ended = new CountDownLatch(1);
        volatile boolean completed;

        void add(T event) { events.add(event); }
        void fail(Throwable e) { error.set(e); ended.countDown(); }
        void done() { completed = true; ended.countDown(); }

        Outcome<T> await() throws InterruptedException {
            assertTrue(ended.await(10, TimeUnit.SECONDS), "stream never ended");
            return this;
        }
    }

    @Test
    void everyArgumentShapeRoundTrips() throws InterruptedException {
        Outcome<SubEchoArgsResponse> o = new Outcome<>();
        disposers.add(Rx.subscribe(client.subscriptions.subEchoArgs(
            List.of(1, 2), Arrays.asList(1, null), List.of(List.of(1), List.of(), List.of(2, 3)),
            List.of(Spelling.X_Y, Spelling.HTTP2_OK), Arrays.asList(null, Spelling.V1), null, null),
            o::add, o::fail, o::done));
        o.await();
        assertEquals(1, o.events.size());
        ListsEcho r = o.events.get(0).getSubEchoArgs();
        assertEquals(List.of(1, 2), r.getA());
        assertEquals(Arrays.asList(1, null), r.getB());
        assertEquals(List.of(List.of(1), List.of(), List.of(2, 3)), r.getC());
        assertEquals(List.of(Spelling.X_Y, Spelling.HTTP2_OK), r.getE());
        assertEquals(Arrays.asList(null, Spelling.V1), r.getF());
        assertTrue(o.completed);
    }

    @Test
    void omittedArgumentsAreNullAndDefaultsApply() throws InterruptedException {
        Outcome<SubEchoArgsResponse> o = new Outcome<>();
        disposers.add(Rx.subscribe(client.subscriptions.subEchoArgs(
            List.of(), null, null, List.of(), null, null, null), o::add, o::fail, o::done));
        o.await();
        ListsEcho r = o.events.get(0).getSubEchoArgs();
        assertNull(r.getB());
        assertNull(r.getC());
        assertNull(r.getF());
        assertEquals(List.of(Spelling.A, Spelling.B2), r.getG());
        assertEquals(OnlyOne.ONLY, r.getOne());
    }

    @Test
    void inputObjectRoundTrips() throws InterruptedException {
        ListsInput input = new ListsInput(
            List.of(3, 4), Arrays.asList(null, 5), List.of(List.of(1, 2), List.of()),
            List.of(Spelling.SNAKE_CASE_2), Arrays.asList(Spelling.A, null), List.of(Spelling.V1), null);
        Outcome<SubEchoInputResponse> o = new Outcome<>();
        disposers.add(Rx.subscribe(client.subscriptions.subEchoInput(input), o::add, o::fail, o::done));
        o.await();
        ListsEcho r = o.events.get(0).getSubEchoInput();
        assertEquals(List.of(3, 4), r.getA());
        assertEquals(Arrays.asList(null, 5), r.getB());
        assertEquals(List.of(List.of(1, 2), List.of()), r.getC());
        assertEquals(List.of(Spelling.SNAKE_CASE_2), r.getE());
        assertEquals(Arrays.asList(Spelling.A, null), r.getF());
        assertEquals(List.of(Spelling.V1), r.getG());
    }

    @Test
    void serverCompletionDeliversEveryEventThenCompletes() throws InterruptedException {
        Outcome<FiniteTicksResponse> o = new Outcome<>();
        disposers.add(Rx.subscribe(client.subscriptions.finiteTicks(5), o::add, o::fail, o::done));
        o.await();
        assertEquals(List.of(1, 2, 3, 4, 5), o.events.stream().map(FiniteTicksResponse::getFiniteTicks).toList());
        assertTrue(o.completed);
        assertNull(o.error.get());
    }

    @Test
    void completionWithoutEventsStillCompletes() throws InterruptedException {
        Outcome<FiniteTicksResponse> o = new Outcome<>();
        disposers.add(Rx.subscribe(client.subscriptions.finiteTicks(0), o::add, o::fail, o::done));
        o.await();
        assertTrue(o.events.isEmpty());
        assertTrue(o.completed);
    }

    @Test
    void eventsBeforeTheFailureArriveThenTheError() throws InterruptedException {
        Outcome<FlakyTicksResponse> o = new Outcome<>();
        disposers.add(Rx.subscribe(client.subscriptions.flakyTicks(3), o::add, o::fail, o::done));
        o.await();
        assertEquals(List.of(1, 2, 3), o.events.stream().map(FlakyTicksResponse::getFlakyTicks).toList());
        assertNotNull(o.error.get());
        assertFalse(o.completed);
    }

    @Test
    void failureBeforeTheFirstEvent() throws InterruptedException {
        Outcome<FlakyTicksResponse> o = new Outcome<>();
        disposers.add(Rx.subscribe(client.subscriptions.flakyTicks(0), o::add, o::fail, o::done));
        o.await();
        assertTrue(o.events.isEmpty());
        assertNotNull(o.error.get());
    }
}
