package dev.graphlink.test;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.graphlink.test.generated.client.DefaultGraphLinkClientAdapter;
import dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter;
import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.client.JacksonGraphLinkJsonCodec;
import org.junit.jupiter.api.DynamicTest;
import org.junit.jupiter.api.Timeout;
import org.junit.jupiter.api.TestFactory;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

@Timeout(value = 5, unit = TimeUnit.MINUTES)
class WsFaultsStreamsTest {

    private static final int FAULT_PORT = Integer.parseInt(System.getenv().getOrDefault("WS_FAULT_PORT", "9948"));
    private static final String FAULT_URL = "http://127.0.0.1:" + FAULT_PORT;
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final HttpClient HTTP = HttpClient.newHttpClient();

    private static final Map<String, String> KNOWN_DEFECTS = Map.of();

    private static String send(String method, String path) throws Exception {
        HttpRequest.Builder request = HttpRequest.newBuilder(URI.create(FAULT_URL + path));
        request = method.equals("POST") ? request.POST(HttpRequest.BodyPublishers.noBody()) : request.GET();
        return HTTP.send(request.build(), HttpResponse.BodyHandlers.ofString()).body();
    }

    @TestFactory
    Stream<DynamicTest> websocketFaults() throws Exception {
        JsonNode cases = JSON.readTree(Files.readString(Path.of("../../fault_server/ws_cases.json")));
        List<DynamicTest> tests = new ArrayList<>();
        for (JsonNode c : cases) {
            String fault = c.get("fault").asText();
            tests.add(DynamicTest.dynamicTest(fault, () -> {
                assumeTrue(!KNOWN_DEFECTS.containsKey(fault), KNOWN_DEFECTS.get(fault));
                run(c, fault);
            }));
        }
        return tests.stream();
    }

    private void run(JsonNode c, String fault) throws Exception {
        send("POST", "/_reset");
        send("POST", "/_arm?fault=" + fault + "&times=" + c.path("times").asInt(1));
        JacksonGraphLinkJsonCodec codec = new JacksonGraphLinkJsonCodec();
        DefaultGraphLinkWebSocketAdapter ws = new DefaultGraphLinkWebSocketAdapter("ws://127.0.0.1:" + FAULT_PORT + "/graphql", null, 10, 30_000);
        GraphLinkClient client = new GraphLinkClient(new DefaultGraphLinkClientAdapter(FAULT_URL + "/graphql", codec), null, codec, codec, ws);
        List<Integer> events = new CopyOnWriteArrayList<>();
        AtomicReference<Throwable> error = new AtomicReference<>();
        AtomicBoolean settled = new AtomicBoolean();
        AtomicReference<Runnable> disposer = new AtomicReference<>(() -> {});
        try {
            Runnable dispose = Rx.subscribe(client.subscriptions.counterTick(),
                    response -> events.add(response.getCounterTick()),
                    e -> { error.set(e); settled.set(true); },
                    () -> settled.set(true));
            disposer.set(dispose);
            boolean fixedWait = c.has("waitSeconds");
            long deadline = System.currentTimeMillis() + c.path("waitSeconds").asInt(8) * 1000L;
            while (!settled.get() && System.currentTimeMillis() < deadline) Thread.sleep(100);

            JsonNode log = JSON.readTree(send("GET", "/_ws_log"));
            List<String> sent = new ArrayList<>();
            for (JsonNode connection : log) for (JsonNode frame : connection.get("frames")) sent.add(frame.get("type").asText());

            if (!fixedWait) {
                assertTrue(settled.get(), fault + ": the subscription hung");
                switch (c.get("expect").asText()) {
                    case "value" -> {
                        assertNull(error.get(), fault + ": unexpected failure " + error.get());
                        assertEquals(List.of(1), events, fault);
                    }
                    case "error" -> {
                        assertNotNull(error.get(), fault + ": no failure, events=" + events);
                        if (c.has("message")) {
                            String text = error.get() instanceof dev.graphlink.test.generated.client.GraphLinkException
                                    ? ((dev.graphlink.test.generated.client.GraphLinkException) error.get()).getErrors().stream().map(e -> e.getMessage()).collect(java.util.stream.Collectors.joining())
                                    : String.valueOf(error.get().getMessage());
                            assertTrue(text.contains(c.get("message").asText()), fault + ": failure does not mention " + c.get("message").asText() + ": " + text);
                        }
                    }
                    default -> { }
                }
            }
            if (c.path("noSubscribeBeforeAck").asBoolean()) assertFalse(sent.contains("subscribe"), fault + ": subscribe before the ack");
            if (c.path("pong").asBoolean()) assertTrue(sent.contains("pong"), fault + ": ping not answered");
            if (c.has("maxConnections")) assertTrue(log.size() <= c.get("maxConnections").asInt(), fault + ": " + log.size() + " connections");
            if (c.has("minConnections")) assertTrue(log.size() >= c.get("minConnections").asInt(), fault + ": " + log.size() + " connections");
        } finally {
            disposer.get().run();
            ws.close();
        }
    }
}
