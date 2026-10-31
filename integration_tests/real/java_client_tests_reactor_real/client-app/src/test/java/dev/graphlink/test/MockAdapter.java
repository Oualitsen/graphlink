package dev.graphlink.test;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.graphlink.test.generated.interfaces.GraphLinkClientAdapter;
import reactor.core.publisher.Mono;

import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Drop-in adapter for GraphLinkClient that returns pre-registered responses
 * and records every outgoing request for assertion.
 *
 * Usage:
 *   MockAdapter adapter = new MockAdapter();
 *   adapter.registerData("getUser", Map.of("getUser", userJson));
 *   GraphLinkClient client = new GraphLinkClient(adapter, encoder, decoder, wsAdapter);
 *   // ... call client methods ...
 *   assertEquals(1, adapter.getCallCount());
 *   assertEquals("user-1", adapter.getLastCall().variables().get("id"));
 */
public class MockAdapter implements GraphLinkClientAdapter {

    private static final Pattern OPERATION_NAME_PATTERN =
            Pattern.compile("(?:query|mutation|subscription)\\s+(\\w+)");

    private static final ObjectMapper MAPPER = new ObjectMapper();

    private final Map<String, String> responses = new LinkedHashMap<>();
    private final List<GraphLinkCall> calls = new ArrayList<>();

    /** Set to true to make every call throw — used for staleIfOffline tests. */
    public volatile boolean simulateFailure = false;

    // ── Registration ──────────────────────────────────────────────────────────

    /** Register a raw JSON string response for the given operation name. */
    public void register(String operationName, String jsonResponse) {
        responses.put(operationName, jsonResponse);
    }

    /** Wraps data as {"data": data} and registers it. */
    public void registerData(String operationName, Map<String, Object> data) {
        try {
            register(operationName, MAPPER.writeValueAsString(Map.of("data", data)));
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    /** Registers a response with both data and errors (partial-success / error-capture case). */
    public void registerDataAndErrors(String operationName, Map<String, Object> data,
                                      List<Map<String, Object>> errors) {
        try {
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("data", data);
            body.put("errors", errors);
            register(operationName, MAPPER.writeValueAsString(body));
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    /** Registers a GraphQL error response (data is null). */
    public void registerErrors(String operationName, List<Map<String, Object>> errors) {
        try {
            Map<String, Object> body = new LinkedHashMap<>();
            body.put("data", null);
            body.put("errors", errors);
            register(operationName, MAPPER.writeValueAsString(body));
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    // ── Assertion helpers ─────────────────────────────────────────────────────

    public List<GraphLinkCall> getCalls() {
        return Collections.unmodifiableList(calls);
    }

    public GraphLinkCall getLastCall() {
        return calls.isEmpty() ? null : calls.get(calls.size() - 1);
    }

    public int getCallCount() {
        return calls.size();
    }

    public void reset() {
        calls.clear();
        responses.clear();
        simulateFailure = false;
    }

    // ── GraphLinkClientAdapter ────────────────────────────────────────────────

    // Reactive variant: returns a deferred Mono so that simulated failures and
    // missing-response errors surface as error signals (caught by the cache's
    // onErrorResume / propagated through .block()), exactly like a real
    // reactive transport. The work is deferred to subscription time.
    @Override
    public Mono<String> execute(String payload) {
        return Mono.fromCallable(() -> {
            if (simulateFailure) throw new RuntimeException("Simulated network failure");

            try {
                @SuppressWarnings("unchecked")
                Map<String, Object> decoded = MAPPER.readValue(payload, Map.class);
                String query = (String) decoded.getOrDefault("query", "");
                @SuppressWarnings("unchecked")
                Map<String, Object> variables = (Map<String, Object>) decoded.getOrDefault("variables", Map.of());
                String opName = extractOperationName(query);

                calls.add(new GraphLinkCall(opName, variables, payload));

                if (opName != null && responses.containsKey(opName)) {
                    return responses.get(opName);
                }
                throw new IllegalStateException(
                        "MockAdapter: no response registered for \"" + (opName != null ? opName : "unknown") + "\".\n" +
                        "Registered operations: " + responses.keySet() + "\n" +
                        "Payload: " + payload
                );
            } catch (RuntimeException e) {
                throw e;
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        });
    }

    // ── Internal ──────────────────────────────────────────────────────────────

    private static String extractOperationName(String query) {
        Matcher m = OPERATION_NAME_PATTERN.matcher(query.trim());
        return m.find() ? m.group(1) : null;
    }
}
