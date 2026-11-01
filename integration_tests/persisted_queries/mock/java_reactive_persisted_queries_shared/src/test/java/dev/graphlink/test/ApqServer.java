package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkGetNotSupported;
import dev.graphlink.test.generated.client.GraphLinkSha256;
import dev.graphlink.test.generated.client.JacksonGraphLinkJsonCodec;
import dev.graphlink.test.generated.interfaces.GraphLinkClientAdapter;

import java.util.*;

public class ApqServer {
    private final JacksonGraphLinkJsonCodec codec = new JacksonGraphLinkJsonCodec();
    private final Map<String, Map<String, Object>> responses = new HashMap<>();
    private final Set<String> registered = new HashSet<>();

    public final List<Map<String, Object>> requests = new ArrayList<>();
    public final List<String> methods = new ArrayList<>();

    public boolean supported = true;
    public boolean getSupported = true;
    public String notFoundMessage = "PersistedQueryNotFound";
    public RuntimeException failWith;
    public RuntimeException getFailWith;

    public final GraphLinkClientAdapter post = payload -> Reactive.fromSupplier(() -> handle("POST", payload, failWith));

    public final GraphLinkClientAdapter get = payload -> Reactive.fromSupplier(() -> {
        if (!getSupported) {
            methods.add("GET");
            throw new GraphLinkGetNotSupported("GET is not allowed");
        }
        return handle("GET", payload, getFailWith);
    });

    public void respondTo(String operationName, Map<String, Object> data) {
        Map<String, Object> response = new HashMap<>();
        response.put("data", data);
        responses.put(operationName, response);
    }

    public void respondWithErrors(String operationName, List<Map<String, Object>> errors) {
        Map<String, Object> response = new HashMap<>();
        response.put("data", null);
        response.put("errors", errors);
        responses.put(operationName, response);
    }

    public void evict() {
        registered.clear();
    }

    public void clearRequests() {
        requests.clear();
        methods.clear();
    }

    public boolean isHashOnly(Map<String, Object> body) {
        return body.containsKey("extensions") && !body.containsKey("query");
    }

    @SuppressWarnings("unchecked")
    private String handle(String method, String payload, RuntimeException failure) {
        methods.add(method);
        Map<String, Object> body = codec.decode(payload);
        requests.add(body);
        if (failure != null) throw failure;

        Map<String, Object> extensions = (Map<String, Object>) body.get("extensions");
        Map<String, Object> persisted = extensions == null ? null : (Map<String, Object>) extensions.get("persistedQuery");
        if (persisted != null) {
            if (!supported) return error("PersistedQueryNotSupported", "PERSISTED_QUERY_NOT_SUPPORTED");
            String hash = (String) persisted.get("sha256Hash");
            String query = (String) body.get("query");
            if (query == null) {
                if (!registered.contains(hash)) return error(notFoundMessage, "PERSISTED_QUERY_NOT_FOUND");
            } else {
                if (!GraphLinkSha256.hex(query).equals(hash)) return error("provided sha does not match query", "INTERNAL_SERVER_ERROR");
                registered.add(hash);
            }
        }
        String operationName = (String) body.get("operationName");
        Map<String, Object> response = responses.get(operationName);
        if (response == null) throw new IllegalStateException("No response registered for " + operationName);
        return codec.encode(response);
    }

    private String error(String message, String code) {
        Map<String, Object> details = new HashMap<>();
        details.put("code", code);
        Map<String, Object> error = new HashMap<>();
        error.put("message", message);
        error.put("extensions", details);
        return codec.encode(Map.of("errors", List.of(error)));
    }
}
