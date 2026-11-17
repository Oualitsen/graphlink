package dev.graphlink.test;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.graphlink.test.generated.client.DefaultGraphLinkClientAdapter;
import dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter;
import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.client.JacksonGraphLinkJsonCodec;
import dev.graphlink.test.generated.types.FetchBigUsersResponse;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

@Timeout(value = 2, unit = TimeUnit.MINUTES)
class HugeResponseTest {

    private static final int FAULT_PORT = Integer.parseInt(System.getenv().getOrDefault("WS_FAULT_PORT", "9946"));
    private static final String FAULT_URL = "http://127.0.0.1:" + FAULT_PORT;

    private static void post(String path) throws Exception {
        HttpClient.newHttpClient().send(
                HttpRequest.newBuilder(URI.create(FAULT_URL + path)).POST(HttpRequest.BodyPublishers.noBody()).build(),
                HttpResponse.BodyHandlers.discarding());
    }

    @Test
    void aTenMegabyteResponseIsDecodedWithoutLoss() throws Exception {
        JsonNode expected = new ObjectMapper().readTree(Files.readString(Path.of("../../fault_server/huge_case.json")));
        int users = expected.get("users").asInt();
        post("/_reset");
        post("/_arm?fault=huge-users");
        JacksonGraphLinkJsonCodec codec = new JacksonGraphLinkJsonCodec();
        GraphLinkClient client = new GraphLinkClient(new DefaultGraphLinkClientAdapter(FAULT_URL + "/graphql", codec), null, codec, codec, new DefaultGraphLinkWebSocketAdapter("ws://127.0.0.1:" + FAULT_PORT + "/graphql"));

        long started = System.nanoTime();
        FetchBigUsersResponse response = client.queries.fetchBigUsers(users);
        long elapsedMs = (System.nanoTime() - started) / 1_000_000;

        var list = response.getBigUsers();
        assertEquals(users, list.size());
        assertEquals("user-0", list.get(0).getId());
        assertEquals("User " + (users - 1) + " Ünï 日本", list.get(users - 1).getName());
        assertEquals("user-" + (users - 1) + "@example.com", list.get(users - 1).getEmail());
        assertEquals("INACTIVE", list.get(1).getStatus().toString());
        assertEquals(List.of("alpha", "beta"), list.get(users / 2).getTags());
        assertNull(list.get(0).getAddress().getZip());
        assertTrue(elapsedMs < 30_000, "decoding took " + elapsedMs + " ms");

        post("/_arm?fault=huge-users");
        assertEquals(users, client.queries.fetchBigUsers(users).getBigUsers().size());
    }
}
