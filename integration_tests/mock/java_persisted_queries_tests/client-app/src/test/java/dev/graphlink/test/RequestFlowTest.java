package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.client.GraphLinkSha256;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class RequestFlowTest {
    private ApqServer server;
    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        server = new ApqServer();
        client = Helpers.newClient(server);
    }

    @Nested
    class LongQuery {
        @BeforeEach
        void register() {
            server.respondTo("persistedLongQuery", map("getUser", kUserAliceJson));
        }

        @Test
        void isSentAsAHashFirstAndRegisteredByTheRetry() {
            var res = client.queries.persistedLongQuery("user-1");

            assertEquals("Alice Smith", res.getGetUser().getName());
            assertEquals(2, server.requests.size());
            assertFalse(server.requests.get(0).containsKey("query"));
            assertEquals("persistedLongQuery", server.requests.get(0).get("operationName"));
            assertEquals(Map.of("id", "user-1"), server.requests.get(0).get("variables"));
            assertInstanceOf(String.class, server.requests.get(1).get("query"));
            assertEquals(Map.of("id", "user-1"), server.requests.get(1).get("variables"));
        }

        @Test
        void theHashIsTheSha256OfTheQueryTheRetryCarries() {
            client.queries.persistedLongQuery("user-1");

            Map<String, Object> retry = server.requests.get(1);
            assertEquals(1, Helpers.hashOf(retry).get("version"));
            assertEquals(GraphLinkSha256.hex((String) retry.get("query")), Helpers.hashOf(retry).get("sha256Hash"));
            assertEquals(Helpers.hashOf(retry), Helpers.hashOf(server.requests.get(0)));
        }

        @Test
        void isASingleRequestOnceTheServerKnowsIt() {
            client.queries.persistedLongQuery("user-1");
            server.clearRequests();

            client.queries.persistedLongQuery("user-2");

            assertEquals(1, server.requests.size());
            assertTrue(server.isHashOnly(server.requests.get(0)));
            assertEquals(Map.of("id", "user-2"), server.requests.get(0).get("variables"));
        }

        @Test
        void isRegisteredAgainAfterTheServerEvictsIt() {
            client.queries.persistedLongQuery("user-1");
            server.evict();
            server.clearRequests();

            var res = client.queries.persistedLongQuery("user-1");

            assertEquals("Alice Smith", res.getGetUser().getName());
            assertEquals(2, server.requests.size());
            assertTrue(server.isHashOnly(server.requests.get(0)));
            assertTrue(server.requests.get(1).containsKey("query"));
        }
    }

    @Test
    void aShortQueryIsSentInFullWithNoHash() {
        server.respondTo("persistedShortQuery", map("listUsers", List.of()));

        client.queries.persistedShortQuery();

        assertEquals(1, server.requests.size());
        assertTrue(((String) server.requests.get(0).get("query")).contains("listUsers"));
        assertFalse(server.requests.get(0).containsKey("extensions"));
    }

    @Test
    void aLongMutationUsesTheSameHashThenRegisterFlow() {
        server.respondTo("persistedLongMutation", map("createUser", kUserAliceJson));

        var res = client.mutations.persistedLongMutation(Helpers.createUserInput());

        assertEquals("Alice Smith", res.getCreateUser().getName());
        assertEquals(2, server.requests.size());
        assertTrue(server.isHashOnly(server.requests.get(0)));
        assertTrue(server.requests.get(1).containsKey("query"));
    }

    @Nested
    class ServerWithoutApq {
        @BeforeEach
        void register() {
            server.supported = false;
            server.respondTo("persistedLongQuery", map("getUser", kUserAliceJson));
        }

        @Test
        void getsTheFullQueryRightAfterTheFirstRefusal() {
            var res = client.queries.persistedLongQuery("user-1");

            assertEquals("Alice Smith", res.getGetUser().getName());
            assertEquals(2, server.requests.size());
            assertTrue(server.requests.get(1).containsKey("query"));
            assertFalse(server.requests.get(1).containsKey("extensions"));
        }

        @Test
        void isNotAskedAboutHashesAgain() {
            client.queries.persistedLongQuery("user-1");
            server.clearRequests();

            client.queries.persistedLongQuery("user-2");

            assertEquals(1, server.requests.size());
            assertTrue(server.requests.get(0).containsKey("query"));
            assertFalse(server.requests.get(0).containsKey("extensions"));
        }
    }

    @Test
    void aServerThatReportsAMissingHashOnlyByItsCodeStillGetsTheRetry() {
        server.notFoundMessage = "Unknown query";
        server.respondTo("persistedLongQuery", map("getUser", kUserAliceJson));

        var res = client.queries.persistedLongQuery("user-1");

        assertEquals("Alice Smith", res.getGetUser().getName());
        assertEquals(2, server.requests.size());
        assertTrue(server.requests.get(1).containsKey("query"));
    }

    @Test
    void aGraphQLErrorIsReturnedAsIsWithoutASecondRequest() {
        server.respondTo("persistedLongQuery", map("getUser", kUserAliceJson));
        client.queries.persistedLongQuery("user-1");
        server.clearRequests();
        server.respondWithErrors("persistedLongQuery", List.of(map("message", "boom")));

        assertThrows(RuntimeException.class, () -> client.queries.persistedLongQuery("user-1"));
        assertEquals(1, server.requests.size());
    }

    @Test
    void aTransportFailurePropagatesWithoutASecondRequest() {
        server.respondTo("persistedLongMutation", map("createUser", kUserAliceJson));
        server.failWith = new IllegalStateException("timeout");

        var e = assertThrows(IllegalStateException.class,
                () -> client.mutations.persistedLongMutation(Helpers.createUserInput()));
        assertEquals("timeout", e.getMessage());
        assertEquals(List.of("POST"), server.methods);
    }

    @Test
    void aCachedQueryHashesTheAssembledRequestNotItsPieces() {
        server.respondTo("fetchCachedPair", map("user", kUserAliceJson, "post", kPostJson));

        var res = client.queries.fetchCachedPair("user-1", "post-1");

        assertEquals("Alice Smith", res.getUser().getName());
        assertEquals(2, server.requests.size());
        Map<String, Object> retry = server.requests.get(1);
        assertEquals(GraphLinkSha256.hex((String) retry.get("query")), Helpers.hashOf(retry).get("sha256Hash"));
        assertTrue(((String) retry.get("query")).contains("getCachedUser"));
    }
}
