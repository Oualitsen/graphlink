package dev.graphlink.test;

import dev.graphlink.test.generated.client.DefaultGraphLinkClientAdapter;
import dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter;
import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.client.GraphLinkSubscriptionListener;
import dev.graphlink.test.generated.client.JacksonGraphLinkJsonCodec;
import dev.graphlink.test.generated.enums.UserStatus;
import dev.graphlink.test.generated.types.UserCreatedResponse;
import dev.graphlink.test.generated.types.UserCreatedsResponse;
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

    // ── MultipleIdenticalSubscriptions ────────────────────────────────────────
    // Same operation + same variables registered twice — each call gets its own
    // UUID so both receive independent streams from the server.

    @Nested
    class MultipleIdenticalSubscriptions {

        @Test
        void userCreated_registeredTwice_bothReceiveAllEvents() throws InterruptedException {
            CountDownLatch latch1 = new CountDownLatch(2);
            CountDownLatch latch2 = new CountDownLatch(2);
            List<UserCreatedResponse> events1 = new CopyOnWriteArrayList<>();
            List<UserCreatedResponse> events2 = new CopyOnWriteArrayList<>();

            // Both registered before either latch is awaited.
            client.subscriptions.userCreated(new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserCreatedResponse r) { events1.add(r); latch1.countDown(); }
            });
            client.subscriptions.userCreated(new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserCreatedResponse r) { events2.add(r); latch2.countDown(); }
            });

            assertTrue(latch1.await(10, TimeUnit.SECONDS), "Subscription 1 timed out");
            assertTrue(latch2.await(10, TimeUnit.SECONDS), "Subscription 2 timed out");
            assertEquals("user-1", events1.get(0).getUserCreated().getId());
            assertEquals("user-2", events1.get(1).getUserCreated().getId());
            assertEquals("user-1", events2.get(0).getUserCreated().getId());
            assertEquals("user-2", events2.get(1).getUserCreated().getId());
        }

        @Test
        void userStatusChanged_sameArg_registeredTwice_bothReceiveEvent() throws InterruptedException {
            CountDownLatch latch1 = new CountDownLatch(1);
            CountDownLatch latch2 = new CountDownLatch(1);
            List<UserStatusChangedResponse> events1 = new CopyOnWriteArrayList<>();
            List<UserStatusChangedResponse> events2 = new CopyOnWriteArrayList<>();

            client.subscriptions.userStatusChanged("user-1", new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserStatusChangedResponse r) { events1.add(r); latch1.countDown(); }
            });
            client.subscriptions.userStatusChanged("user-1", new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserStatusChangedResponse r) { events2.add(r); latch2.countDown(); }
            });

            assertTrue(latch1.await(10, TimeUnit.SECONDS), "Subscription 1 timed out");
            assertTrue(latch2.await(10, TimeUnit.SECONDS), "Subscription 2 timed out");
            assertEquals("user-1", events1.get(0).getUserStatusChanged().getId());
            assertEquals(UserStatus.ACTIVE, events1.get(0).getUserStatusChanged().getStatus());
            assertEquals("user-1", events2.get(0).getUserStatusChanged().getId());
            assertEquals(UserStatus.ACTIVE, events2.get(0).getUserStatusChanged().getStatus());
        }
    }

    // ── MultipleDifferentSubscriptions ────────────────────────────────────────
    // Different operations or same operation with different args — verifies that
    // UUID-based routing delivers each event only to the correct listener.

    @Nested
    class MultipleDifferentSubscriptions {

        @Test
        void userCreated_and_userStatusChanged_runConcurrently() throws InterruptedException {
            CountDownLatch latch1 = new CountDownLatch(1);
            CountDownLatch latch2 = new CountDownLatch(1);
            List<UserCreatedResponse> userCreatedEvents = new CopyOnWriteArrayList<>();
            List<UserStatusChangedResponse> statusEvents = new CopyOnWriteArrayList<>();

            client.subscriptions.userCreated(new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserCreatedResponse r) { userCreatedEvents.add(r); latch1.countDown(); }
            });
            client.subscriptions.userStatusChanged("user-1", new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserStatusChangedResponse r) { statusEvents.add(r); latch2.countDown(); }
            });

            assertTrue(latch1.await(10, TimeUnit.SECONDS), "userCreated timed out");
            assertTrue(latch2.await(10, TimeUnit.SECONDS), "userStatusChanged timed out");
            assertEquals("user-1", userCreatedEvents.get(0).getUserCreated().getId());
            assertEquals("user-1", statusEvents.get(0).getUserStatusChanged().getId());
            assertEquals(UserStatus.ACTIVE, statusEvents.get(0).getUserStatusChanged().getStatus());
        }

        @Test
        void userStatusChanged_differentArgs_receiveIndependentEvents() throws InterruptedException {
            CountDownLatch latch1 = new CountDownLatch(1);
            CountDownLatch latch2 = new CountDownLatch(1);
            List<UserStatusChangedResponse> events1 = new CopyOnWriteArrayList<>();
            List<UserStatusChangedResponse> events2 = new CopyOnWriteArrayList<>();

            client.subscriptions.userStatusChanged("user-1", new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserStatusChangedResponse r) { events1.add(r); latch1.countDown(); }
            });
            client.subscriptions.userStatusChanged("user-2", new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserStatusChangedResponse r) { events2.add(r); latch2.countDown(); }
            });

            assertTrue(latch1.await(10, TimeUnit.SECONDS));
            assertTrue(latch2.await(10, TimeUnit.SECONDS));
            assertEquals("user-1", events1.get(0).getUserStatusChanged().getId());
            assertEquals(UserStatus.ACTIVE, events1.get(0).getUserStatusChanged().getStatus());
            assertEquals("user-2", events2.get(0).getUserStatusChanged().getId());
            assertEquals(UserStatus.INACTIVE, events2.get(0).getUserStatusChanged().getStatus());
        }

        @Test
        void userCreated_and_userCreateds_runConcurrently() throws InterruptedException {
            CountDownLatch latch1 = new CountDownLatch(1);
            CountDownLatch latch2 = new CountDownLatch(1);
            List<UserCreatedResponse> singleEvents = new CopyOnWriteArrayList<>();
            List<UserCreatedsResponse> listEvents = new CopyOnWriteArrayList<>();

            client.subscriptions.userCreated(new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserCreatedResponse r) { singleEvents.add(r); latch1.countDown(); }
            });
            client.subscriptions.userCreateds(List.of("user-1", "user-2"), new GraphLinkSubscriptionListener<>() {
                @Override public void onMessage(UserCreatedsResponse r) { listEvents.add(r); latch2.countDown(); }
            });

            assertTrue(latch1.await(10, TimeUnit.SECONDS));
            assertTrue(latch2.await(10, TimeUnit.SECONDS));
            assertEquals("user-1", singleEvents.get(0).getUserCreated().getId());
            assertNotNull(listEvents.get(0).getUserCreateds());
            assertEquals(2, listEvents.get(0).getUserCreateds().size());
            assertEquals("user-1", listEvents.get(0).getUserCreateds().get(0).getId());
            assertEquals("user-2", listEvents.get(0).getUserCreateds().get(1).getId());
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
