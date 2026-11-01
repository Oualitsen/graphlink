package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Set;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class GetAdapterTest {
    private ApqServer server;
    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        server = new ApqServer();
        client = Helpers.newClient(server);
        server.respondTo("persistedLongQuery", map("getUser", kUserAliceJson));
        server.respondTo("persistedShortQuery", map("listUsers", List.of()));
        server.respondTo("persistedLongMutation", map("createUser", kUserAliceJson));
    }

    @Test
    void aLongQueryAsksWithAGetFirstAndRegistersWithAPost() {
        Reactive.await(client.queries.persistedLongQuery("user-1"));

        assertEquals(List.of("GET", "POST"), server.methods);
        assertTrue(server.isHashOnly(server.requests.get(0)));
        assertTrue(server.requests.get(1).containsKey("query"));
    }

    @Test
    void aLongQueryIsASingleGetOnceTheServerKnowsIt() {
        Reactive.await(client.queries.persistedLongQuery("user-1"));
        server.clearRequests();

        Reactive.await(client.queries.persistedLongQuery("user-2"));

        assertEquals(List.of("GET"), server.methods);
    }

    @Test
    void theGetAdapterReceivesTheHashOnlyPayloadWithNoQuery() {
        Reactive.await(client.queries.persistedLongQuery("user-1"));

        assertEquals(Set.of("extensions", "operationName", "variables"), server.requests.get(0).keySet());
    }

    @Test
    void aShortQueryIsAPlainPost() {
        Reactive.await(client.queries.persistedShortQuery());

        assertEquals(List.of("POST"), server.methods);
    }

    @Test
    void aMutationSendsItsHashOverPost() {
        Reactive.await(client.mutations.persistedLongMutation(Helpers.createUserInput()));

        assertEquals(List.of("POST", "POST"), server.methods);
        assertTrue(server.isHashOnly(server.requests.get(0)));
    }

    @Test
    void aServerRefusingGetGetsTheSameHashOnlyRequestAsAPost() {
        server.getSupported = false;

        var res = Reactive.await(client.queries.persistedLongQuery("user-1"));

        assertEquals("Alice Smith", res.getGetUser().getName());
        assertEquals(List.of("GET", "POST", "POST"), server.methods);
        assertEquals(2, server.requests.size());
        assertTrue(server.isHashOnly(server.requests.get(0)));
        assertTrue(server.requests.get(1).containsKey("query"));
    }

    @Test
    void aServerThatRefusedGetIsNotAskedWithAGetAgain() {
        server.getSupported = false;
        Reactive.await(client.queries.persistedLongQuery("user-1"));
        server.clearRequests();

        Reactive.await(client.queries.persistedLongQuery("user-2"));

        assertEquals(List.of("POST"), server.methods);
    }

    @Test
    void aServerWithoutApqAnswersTheGetWithARefusalThenGetsTheFullQueryByPost() {
        server.supported = false;

        Reactive.await(client.queries.persistedLongQuery("user-1"));

        assertEquals(List.of("GET", "POST"), server.methods);
        assertTrue(server.requests.get(1).containsKey("query"));
        assertFalse(server.requests.get(1).containsKey("extensions"));
    }

    @Test
    void otherGetFailuresPropagateUntouchedWithNoPost() {
        server.getFailWith = new IllegalStateException("network down");

        var e = assertThrows(IllegalStateException.class, () -> Reactive.await(client.queries.persistedLongQuery("user-1")));
        assertEquals("network down", e.getMessage());
        assertEquals(List.of("GET"), server.methods);
    }
}
