package dev.graphlink.test;

import com.sun.net.httpserver.HttpServer;
import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.client.GraphLinkGetNotSupported;
import dev.graphlink.test.generated.client.JacksonGraphLinkJsonCodec;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.*;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class DefaultGetAdapterTest {
    private record Seen(String method, Map<String, String> query, String authorization) {}

    private final JacksonGraphLinkJsonCodec codec = new JacksonGraphLinkJsonCodec();
    private final List<Seen> seen = new ArrayList<>();
    private HttpServer http;
    private ApqServer server;
    private GraphLinkClient client;

    @BeforeEach
    void setUp() throws IOException {
        server = new ApqServer();
        server.respondTo("persistedLongQuery", map("getUser", kUserAliceJson));
        http = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);
        http.createContext("/graphql", exchange -> {
            Map<String, String> params = new LinkedHashMap<>();
            String raw = exchange.getRequestURI().getRawQuery();
            if (raw != null) {
                for (String pair : raw.split("&")) {
                    String[] kv = pair.split("=", 2);
                    params.put(URLDecoder.decode(kv[0], StandardCharsets.UTF_8), URLDecoder.decode(kv[1], StandardCharsets.UTF_8));
                }
            }
            seen.add(new Seen(exchange.getRequestMethod(), params, exchange.getRequestHeaders().getFirst("Authorization")));
            int status = 200;
            String body;
            try {
                if (exchange.getRequestMethod().equals("GET")) {
                    Map<String, Object> payload = new LinkedHashMap<>();
                    if (params.containsKey("operationName")) payload.put("operationName", params.get("operationName"));
                    payload.put("variables", params.containsKey("variables") ? codec.decode(params.get("variables")) : Map.of());
                    payload.put("extensions", codec.decode(params.get("extensions")));
                    body = server.get.execute(codec.encode(payload));
                } else {
                    body = server.post.execute(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
                }
            } catch (GraphLinkGetNotSupported e) {
                status = 405;
                body = "";
            }
            byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(status, bytes.length == 0 ? -1 : bytes.length);
            if (bytes.length > 0) exchange.getResponseBody().write(bytes);
            exchange.close();
        });
        http.start();
        String port = String.valueOf(http.getAddress().getPort());
        client = new GraphLinkClient(
                "http://127.0.0.1:" + port + "/graphql",
                "ws://127.0.0.1:" + port + "/graphql",
                () -> Map.of("Authorization", "Bearer token"),
                codec,
                codec);
    }

    @AfterEach
    void tearDown() {
        http.stop(0);
    }

    private List<String> methods() {
        return seen.stream().map(Seen::method).toList();
    }

    @Test
    void aColdLongQueryIsAGetWithTheHashThenAPostWithTheQuery() {
        var res = client.queries.persistedLongQuery("user-1");

        assertEquals("Alice Smith", res.getGetUser().getName());
        assertEquals(List.of("GET", "POST"), methods());
    }

    @Test
    void theGetCarriesTheOperationItsVariablesAndTheHashInTheUrl() {
        client.queries.persistedLongQuery("user-1");

        Map<String, String> query = seen.get(0).query();
        assertEquals(Set.of("operationName", "variables", "extensions"), query.keySet());
        assertEquals("persistedLongQuery", query.get("operationName"));
        assertEquals(Map.of("id", "user-1"), codec.decode(query.get("variables")));
        @SuppressWarnings("unchecked")
        Map<String, Object> persisted = (Map<String, Object>) codec.decode(query.get("extensions")).get("persistedQuery");
        assertEquals(1, persisted.get("version"));
    }

    @Test
    void aWarmQueryIsASingleGet() {
        client.queries.persistedLongQuery("user-1");
        seen.clear();

        client.queries.persistedLongQuery("user-2");

        assertEquals(List.of("GET"), methods());
    }

    @Test
    void theHeadersProviderAppliesToTheGetAsWell() {
        client.queries.persistedLongQuery("user-1");

        assertEquals("Bearer token", seen.get(0).authorization());
    }

    @Test
    void aPlusInAVariableIsEscapedSoTheServerDoesNotReadItAsASpace() {
        server.respondTo("persistedLongQuery", map("getUser", kUserAliceJson));

        client.queries.persistedLongQuery("a+b@test.com");

        assertEquals(Map.of("id", "a+b@test.com"), codec.decode(seen.get(0).query().get("variables")));
    }

    @Test
    void a405OnGetSendsTheSameRequestAsAPostAndRemembersIt() {
        server.getSupported = false;

        var res = client.queries.persistedLongQuery("user-1");

        assertEquals("Alice Smith", res.getGetUser().getName());
        assertEquals(List.of("GET", "POST", "POST"), methods());
        seen.clear();

        client.queries.persistedLongQuery("user-2");
        assertEquals(List.of("POST"), methods());
    }
}
