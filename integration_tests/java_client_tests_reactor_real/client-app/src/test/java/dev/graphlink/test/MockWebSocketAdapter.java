package dev.graphlink.test;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.graphlink.test.generated.client.GraphLinkWebSocketAdapter;

import java.util.*;
import java.util.function.Consumer;

/**
 * No-op WebSocket adapter for tests that don't use subscriptions, and a
 * fully functional one for tests that do.
 *
 * Protocol flow (graphql-ws):
 *   1. connect() is called → onConnect fires immediately
 *   2. handler sends connection_init → mock replies with connection_ack
 *   3. handler sends subscribe → mock captures the subscription id
 *   4. test calls pushEvent(data) → mock delivers a "next" message
 *   5. test calls pushComplete() → mock delivers a "complete" message
 */
public class MockWebSocketAdapter implements GraphLinkWebSocketAdapter {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    private Consumer<String> messageListener;
    private Runnable reconnectListener;
    private String subscriptionId;
    private final List<Map<String, Object>> sentMessages = new ArrayList<>();

    // ── GraphLinkWebSocketAdapter ─────────────────────────────────────────────

    @Override
    public void connect(Runnable onConnect, Consumer<Throwable> onFailure) {
        onConnect.run();
    }

    @Override
    public void setMessageListener(Consumer<String> listener) {
        this.messageListener = listener;
    }

    @Override
    public void setReconnectListener(Runnable onReconnect) {
        this.reconnectListener = onReconnect;
    }

    @Override
    @SuppressWarnings("unchecked")
    public void sendMessage(String message) {
        try {
            Map<String, Object> decoded = MAPPER.readValue(message, Map.class);
            sentMessages.add(decoded);
            String type = (String) decoded.get("type");

            if ("connection_init".equals(type)) {
                // Reply with connection_ack so the handler proceeds to send subscribe
                deliver("{\"type\":\"connection_ack\"}");
            } else if ("subscribe".equals(type)) {
                subscriptionId = (String) decoded.get("id");
            }
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    @Override
    public void close() {}

    // ── Test API ──────────────────────────────────────────────────────────────

    /**
     * Push a "next" event carrying data for the active subscription.
     * Call this after the subscription has been registered.
     */
    public void pushEvent(Map<String, Object> data) {
        Map<String, Object> payload = Map.of("data", data);
        Map<String, Object> message = new LinkedHashMap<>();
        message.put("type", "next");
        message.put("id", subscriptionId);
        message.put("payload", payload);
        try {
            deliver(MAPPER.writeValueAsString(message));
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    /** Push a "complete" event to signal the subscription is done. */
    public void pushComplete() {
        try {
            deliver(MAPPER.writeValueAsString(Map.of("type", "complete", "id", subscriptionId)));
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    /** Push a graphql-ws "error" event for the given subscription id. */
    public void pushError(String id, List<Map<String, Object>> errors) {
        try {
            Map<String, Object> message = new LinkedHashMap<>();
            message.put("type", "error");
            message.put("id", id);
            message.put("payload", errors);
            deliver(MAPPER.writeValueAsString(message));
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    /** Simulate a reconnect event (re-triggers the handler's re-subscribe logic). */
    public void triggerReconnect() {
        if (reconnectListener != null) reconnectListener.run();
    }

    /** All raw messages sent by the client (connection_init, subscribe, …). */
    public List<Map<String, Object>> getSentMessages() {
        return Collections.unmodifiableList(sentMessages);
    }

    /** The subscription id captured from the last subscribe message. */
    public String getSubscriptionId() {
        return subscriptionId;
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private void deliver(String json) {
        if (messageListener != null) messageListener.accept(json);
    }
}
