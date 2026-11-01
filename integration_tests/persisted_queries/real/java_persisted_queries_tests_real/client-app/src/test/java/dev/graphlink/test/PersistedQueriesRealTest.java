package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.client.JacksonGraphLinkJsonCodec;
import dev.graphlink.test.generated.enums.UserStatus;
import dev.graphlink.test.generated.inputs.AddressInput;
import dev.graphlink.test.generated.inputs.CreateUserInput;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class PersistedQueriesRealTest {
    private static final int PORT = 9997;
    private static final String GRAPHQL = "http://localhost:" + PORT + "/graphql";
    private static final JacksonGraphLinkJsonCodec CODEC = new JacksonGraphLinkJsonCodec();
    private static final HttpClient HTTP = HttpClient.newHttpClient();

    private static final CreateUserInput NEW_USER = CreateUserInput.builder()
            .name("Persisted Pat")
            .email("pat@test.com")
            .status(UserStatus.ACTIVE)
            .address(AddressInput.builder().street("s").city("c").country("x").build())
            .build();

    private GraphLinkClient client;

    @SuppressWarnings("unchecked")
    private static Map<String, Object> control(String method, String path) throws IOException, InterruptedException {
        HttpRequest request = HttpRequest.newBuilder(URI.create("http://localhost:" + PORT + "/test/apq" + path))
                .method(method, HttpRequest.BodyPublishers.noBody())
                .build();
        return (Map<String, Object>) CODEC.decode(HTTP.send(request, HttpResponse.BodyHandlers.ofString()).body());
    }

    private static Map<String, Object> stats() throws IOException, InterruptedException {
        return control("GET", "");
    }

    private static GraphLinkClient newClient() {
        return new GraphLinkClient(GRAPHQL, "ws://localhost:" + PORT + "/graphql", null, CODEC, CODEC);
    }

    @BeforeEach
    void reset() throws Exception {
        control("POST", "/reset");
        client = newClient();
    }

    @Test
    void aLongQueryIsRegisteredOnTheFirstCallAGetMissThenAPostWithTheDocument() throws Exception {
        var res = client.queries.persistedLongQuery("user-1");

        assertEquals("Alice Smith", res.getGetUser().getName());
        var stats = stats();
        assertEquals(1, stats.get("misses"));
        assertEquals(1, stats.get("registrations"));
        assertEquals(1, stats.get("stored"));
        assertEquals(1, stats.get("gets"));
    }

    @Test
    void aLongQueryIsASingleGetHitOnceRegistered() throws Exception {
        client.queries.persistedLongQuery("user-1");

        var res = client.queries.persistedLongQuery("user-1");

        assertEquals("Alice Smith", res.getGetUser().getName());
        var stats = stats();
        assertEquals(1, stats.get("hits"));
        assertEquals(1, stats.get("registrations"));
        assertEquals(2, stats.get("gets"));
    }

    @Test
    void aFreshClientReusesWhatTheServerAlreadyStored() throws Exception {
        client.queries.persistedLongQuery("user-1");

        var res = newClient().queries.persistedLongQuery("user-1");

        assertEquals("Alice Smith", res.getGetUser().getName());
        var stats = stats();
        assertEquals(1, stats.get("hits"));
        assertEquals(1, stats.get("registrations"));
    }

    @Test
    void aLongQueryIsRegisteredAgainAfterTheServerEvictsIt() throws Exception {
        client.queries.persistedLongQuery("user-1");
        control("POST", "/evict");

        var res = client.queries.persistedLongQuery("user-1");

        assertEquals("Alice Smith", res.getGetUser().getName());
        var stats = stats();
        assertEquals(2, stats.get("registrations"));
        assertEquals(1, stats.get("stored"));
    }

    @Test
    void aLongQueryStillWorksWhenTheServerDoesNotSupportPersistedQueries() throws Exception {
        control("POST", "/supported/false");

        var first = client.queries.persistedLongQuery("user-1");
        var second = client.queries.persistedLongQuery("user-1");

        assertEquals("Alice Smith", first.getGetUser().getName());
        assertEquals("Alice Smith", second.getGetUser().getName());
        var stats = stats();
        assertEquals(0, stats.get("stored"));
        assertEquals(1, stats.get("gets"));
    }

    @Test
    void aLongMutationIsRegisteredAndSentOverPostNeverGet() throws Exception {
        var res = client.mutations.persistedLongMutation(NEW_USER);

        assertEquals("Persisted Pat", res.getCreateUser().getName());
        var stats = stats();
        assertEquals(1, stats.get("registrations"));
        assertEquals(0, stats.get("gets"));
    }

    @Test
    void aLongMutationIsAHashOnlyPostOnceRegistered() throws Exception {
        client.mutations.persistedLongMutation(NEW_USER);

        var res = client.mutations.persistedLongMutation(NEW_USER);

        assertEquals("pat@test.com", res.getCreateUser().getEmail());
        var stats = stats();
        assertEquals(1, stats.get("hits"));
        assertEquals(1, stats.get("registrations"));
        assertEquals(0, stats.get("gets"));
    }

    @Test
    void aShortQueryDoesNotUsePersistedQueries() throws Exception {
        var res = client.queries.persistedShortQuery();

        assertFalse(res.getListUsers().isEmpty());
        var stats = stats();
        assertEquals(0, stats.get("hits"));
        assertEquals(0, stats.get("misses"));
        assertEquals(0, stats.get("registrations"));
        assertEquals(0, stats.get("gets"));
    }
}
