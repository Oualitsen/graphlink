package dev.graphlink.test;

import dev.graphlink.test.generated.client.DefaultGraphLinkClientAdapter;
import dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter;
import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.client.GraphLinkSubscriptionListener;
import dev.graphlink.test.generated.client.JacksonGraphLinkJsonCodec;
import dev.graphlink.test.generated.enums.UserStatus;
import dev.graphlink.test.generated.types.UserCreatedResponse;
import dev.graphlink.test.generated.types.UserStatusChangedResponse;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class SubscriptionsTest {

    private DefaultGraphLinkWebSocketAdapter wsAdapter;
    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        JacksonGraphLinkJsonCodec codec = new JacksonGraphLinkJsonCodec();
        wsAdapter = new DefaultGraphLinkWebSocketAdapter(WS_URL);
        client = new GraphLinkClient(
                new DefaultGraphLinkClientAdapter(SERVER_URL),
                null, codec, codec, wsAdapter);
    }

    @AfterEach
    void tearDown() {
        wsAdapter.close();
    }

    // ── userCreated ────────────────────────────────────────────────────────────

    @Nested
    class UserCreated {

        @Test
        void firstEvent_isAlice() throws InterruptedException {
            CountDownLatch latch = new CountDownLatch(1);
            List<UserCreatedResponse> events = new CopyOnWriteArrayList<>();
            client.subscriptions.userCreated(new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserCreatedResponse r) {
                    events.add(r);
                    latch.countDown();
                }
            });
            assertTrue(latch.await(10, TimeUnit.SECONDS), "Timed out waiting for first event");
            assertEquals("user-1", events.get(0).getUserCreated().getId());
        }

        @Test
        void firstEvent_name_isAliceSmith() throws InterruptedException {
            CountDownLatch latch = new CountDownLatch(1);
            List<UserCreatedResponse> events = new CopyOnWriteArrayList<>();
            client.subscriptions.userCreated(new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserCreatedResponse r) {
                    events.add(r);
                    latch.countDown();
                }
            });
            assertTrue(latch.await(10, TimeUnit.SECONDS));
            assertEquals("Alice Smith", events.get(0).getUserCreated().getName());
        }

        @Test
        void firstEvent_status_deserializesToEnum() throws InterruptedException {
            CountDownLatch latch = new CountDownLatch(1);
            List<UserCreatedResponse> events = new CopyOnWriteArrayList<>();
            client.subscriptions.userCreated(new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserCreatedResponse r) {
                    events.add(r);
                    latch.countDown();
                }
            });
            assertTrue(latch.await(10, TimeUnit.SECONDS));
            assertEquals(UserStatus.ACTIVE, events.get(0).getUserCreated().getStatus());
        }

        @Test
        void bothEvents_deliveredInOrder() throws InterruptedException {
            CountDownLatch latch = new CountDownLatch(2);
            List<UserCreatedResponse> events = new CopyOnWriteArrayList<>();
            client.subscriptions.userCreated(new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserCreatedResponse r) {
                    events.add(r);
                    latch.countDown();
                }
            });
            assertTrue(latch.await(10, TimeUnit.SECONDS), "Timed out waiting for both events");
            assertEquals(2, events.size());
            assertEquals("user-1", events.get(0).getUserCreated().getId());
            assertEquals("user-2", events.get(1).getUserCreated().getId());
        }

        @Test
        void onComplete_calledAfterStream() throws InterruptedException {
            CountDownLatch latch = new CountDownLatch(1);
            AtomicBoolean completed = new AtomicBoolean(false);
            client.subscriptions.userCreated(new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserCreatedResponse r) {}
                @Override public void onComplete() {
                    completed.set(true);
                    latch.countDown();
                }
            });
            assertTrue(latch.await(10, TimeUnit.SECONDS), "Timed out waiting for onComplete");
            assertTrue(completed.get());
        }
    }

    // ── userStatusChanged ──────────────────────────────────────────────────────

    @Nested
    class UserStatusChanged {

        @Test
        void event_returnsCorrectUser() throws InterruptedException {
            CountDownLatch latch = new CountDownLatch(1);
            List<UserStatusChangedResponse> events = new CopyOnWriteArrayList<>();
            client.subscriptions.userStatusChanged("user-1", new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserStatusChangedResponse r) {
                    events.add(r);
                    latch.countDown();
                }
            });
            assertTrue(latch.await(10, TimeUnit.SECONDS));
            assertEquals("user-1", events.get(0).getUserStatusChanged().getId());
        }

        @Test
        void event_status_isCorrect() throws InterruptedException {
            CountDownLatch latch = new CountDownLatch(1);
            List<UserStatusChangedResponse> events = new CopyOnWriteArrayList<>();
            client.subscriptions.userStatusChanged("user-1", new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserStatusChangedResponse r) {
                    events.add(r);
                    latch.countDown();
                }
            });
            assertTrue(latch.await(10, TimeUnit.SECONDS));
            assertEquals(UserStatus.ACTIVE, events.get(0).getUserStatusChanged().getStatus());
        }

        @Test
        void onComplete_calledAfterStream() throws InterruptedException {
            CountDownLatch latch = new CountDownLatch(1);
            AtomicBoolean completed = new AtomicBoolean(false);
            client.subscriptions.userStatusChanged("user-1", new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserStatusChangedResponse r) {}
                @Override public void onComplete() {
                    completed.set(true);
                    latch.countDown();
                }
            });
            assertTrue(latch.await(10, TimeUnit.SECONDS));
            assertTrue(completed.get());
        }
    }
}
