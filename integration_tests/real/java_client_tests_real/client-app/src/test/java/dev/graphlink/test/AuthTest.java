package dev.graphlink.test;

import dev.graphlink.test.generated.client.DefaultGraphLinkClientAdapter;
import dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter;
import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.client.GraphLinkException;
import dev.graphlink.test.generated.client.JacksonGraphLinkJsonCodec;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.Supplier;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class AuthTest {

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
}
