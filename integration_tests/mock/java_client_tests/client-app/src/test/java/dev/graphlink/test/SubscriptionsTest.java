package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkException;
import dev.graphlink.test.generated.client.GraphLinkSubscriptionListener;
import dev.graphlink.test.generated.enums.UserStatus;
import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.types.UserCreatedResponse;
import dev.graphlink.test.generated.types.UserStatusChangedResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class SubscriptionsTest {

    private MockAdapter adapter;
    private MockWebSocketAdapter wsAdapter;
    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        adapter = new MockAdapter();
        wsAdapter = new MockWebSocketAdapter();
        client = newClient(adapter, wsAdapter);
    }

    // ── userCreated ────────────────────────────────────────────────────────────

    @Nested
    class UserCreated {

        @Test
        void singleEvent_deserializedCorrectly() {
            List<UserCreatedResponse> events = new ArrayList<>();
            client.subscriptions.userCreated(onMessage(events));

            wsAdapter.pushEvent(Map.of("userCreated", kUserAliceJson));

            assertEquals(1, events.size());
            assertEquals("user-1", events.get(0).getUserCreated().getId());
        }

        @Test
        void singleEvent_name_isCorrect() {
            List<UserCreatedResponse> events = new ArrayList<>();
            client.subscriptions.userCreated(onMessage(events));

            wsAdapter.pushEvent(Map.of("userCreated", kUserAliceJson));

            assertEquals("Alice Smith", events.get(0).getUserCreated().getName());
        }

        @Test
        void singleEvent_status_deserializesToEnum() {
            List<UserCreatedResponse> events = new ArrayList<>();
            client.subscriptions.userCreated(onMessage(events));

            wsAdapter.pushEvent(Map.of("userCreated", kUserAliceJson));

            assertEquals(UserStatus.ACTIVE, events.get(0).getUserCreated().getStatus());
        }

        @Test
        void multipleEvents_deliveredInOrder() {
            List<UserCreatedResponse> events = new ArrayList<>();
            client.subscriptions.userCreated(onMessage(events));

            wsAdapter.pushEvent(Map.of("userCreated", kUserAliceJson));
            wsAdapter.pushEvent(Map.of("userCreated", kUserBobJson));

            assertEquals(2, events.size());
            assertEquals("user-1", events.get(0).getUserCreated().getId());
            assertEquals("user-2", events.get(1).getUserCreated().getId());
        }

        @Test
        void completeMessage_callsOnComplete() {
            AtomicBoolean completed = new AtomicBoolean(false);
            client.subscriptions.userCreated(new GraphLinkSubscriptionListener<UserCreatedResponse>() {
                @Override public void onMessage(UserCreatedResponse r) {}
                @Override public void onComplete() { completed.set(true); }
            });

            wsAdapter.pushComplete();

            assertTrue(completed.get());
        }

        @Test
        void completeMessage_afterEvent_callsOnComplete() {
            List<UserCreatedResponse> events = new ArrayList<>();
            AtomicBoolean completed = new AtomicBoolean(false);
            client.subscriptions.userCreated(new GraphLinkSubscriptionListener<UserCreatedResponse>() {
                @Override public void onMessage(UserCreatedResponse r) { events.add(r); }
                @Override public void onComplete() { completed.set(true); }
            });

            wsAdapter.pushEvent(Map.of("userCreated", kUserAliceJson));
            wsAdapter.pushComplete();

            assertEquals(1, events.size());
            assertTrue(completed.get());
        }

        @Test
        void subscribeMessage_isSent_afterHandshake() {
            client.subscriptions.userCreated(onMessage(new ArrayList<>()));

            long subscribeCount = wsAdapter.getSentMessages().stream()
                    .filter(m -> "subscribe".equals(m.get("type")))
                    .count();
            assertEquals(1, subscribeCount);
        }

        @Test
        void connectionInit_isSent_firstMessage() {
            client.subscriptions.userCreated(onMessage(new ArrayList<>()));

            assertEquals("connection_init", wsAdapter.getSentMessages().get(0).get("type"));
        }
    }

    // ── userStatusChanged ──────────────────────────────────────────────────────

    @Nested
    class UserStatusChanged {

        @Test
        void event_deserializedCorrectly() {
            List<UserStatusChangedResponse> events = new ArrayList<>();
            client.subscriptions.userStatusChanged("user-1", onMessage(events));

            wsAdapter.pushEvent(Map.of("userStatusChanged", kUserAliceJson));

            assertEquals(1, events.size());
            assertEquals("user-1", events.get(0).getUserStatusChanged().getId());
        }

        @Test
        void event_status_isCorrect() {
            List<UserStatusChangedResponse> events = new ArrayList<>();
            client.subscriptions.userStatusChanged("user-1", onMessage(events));

            wsAdapter.pushEvent(Map.of("userStatusChanged", kUserAliceJson));

            assertEquals(UserStatus.ACTIVE, events.get(0).getUserStatusChanged().getStatus());
        }

        @Test
        void userId_sentInSubscribePayload() {
            client.subscriptions.userStatusChanged("user-42", onMessage(new ArrayList<>()));

            Map<String, Object> subscribeMsg = wsAdapter.getSentMessages().stream()
                    .filter(m -> "subscribe".equals(m.get("type")))
                    .findFirst()
                    .orElseThrow();

            @SuppressWarnings("unchecked")
            Map<String, Object> payload = (Map<String, Object>) subscribeMsg.get("payload");
            @SuppressWarnings("unchecked")
            Map<String, Object> variables = (Map<String, Object>) payload.get("variables");
            assertEquals("user-42", variables.get("userId"));
        }

        @Test
        void completeMessage_callsOnComplete() {
            AtomicBoolean completed = new AtomicBoolean(false);
            client.subscriptions.userStatusChanged("user-1", new GraphLinkSubscriptionListener<UserStatusChangedResponse>() {
                @Override public void onMessage(UserStatusChangedResponse r) {}
                @Override public void onComplete() { completed.set(true); }
            });

            wsAdapter.pushComplete();

            assertTrue(completed.get());
        }
    }

    // ── error handling ─────────────────────────────────────────────────────────

    @Nested
    class ErrorHandling {

        @Test
        void errorMessage_callsOnError() {
            AtomicReference<GraphLinkException> caught = new AtomicReference<>();
            client.subscriptions.userCreated(new GraphLinkSubscriptionListener<UserCreatedResponse>() {
                @Override public void onMessage(UserCreatedResponse r) {}
                @Override public void onError(GraphLinkException error) { caught.set(error); }
            });

            wsAdapter.pushError(wsAdapter.getSubscriptionId(),
                    List.of(Map.of("message", "Unauthorized")));

            assertNotNull(caught.get());
        }
    }

    // ── helpers ────────────────────────────────────────────────────────────────

    private static <T> GraphLinkSubscriptionListener<T> onMessage(List<T> collector) {
        return new GraphLinkSubscriptionListener<T>() {
            @Override public void onMessage(T response) { collector.add(response); }
        };
    }
}
