package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.enums.UserStatus;
import dev.graphlink.test.generated.interfaces.SearchResult;
import dev.graphlink.test.generated.types.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class CustomQueriesTest {

    private MockAdapter adapter;
    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        adapter = new MockAdapter();
        client = newClient(adapter, new MockWebSocketAdapter());
    }

    // ── fetchUserAndPost — multi-resolver, single round-trip ──────────────────

    @Nested
    class FetchUserAndPost {

        @BeforeEach
        void register() {
            adapter.registerData("fetchUserAndPost", map(
                    "user", kUserAliceJson,
                    "post", kPostJson
            ));
        }

        @Test
        void response_isNotNull() {
            assertNotNull(client.queries.fetchUserAndPost("user-1", "post-1"));
        }

        @Test
        void user_isNotNull() {
            assertNotNull(client.queries.fetchUserAndPost("user-1", "post-1").getUser());
        }

        @Test
        void user_hasCorrectId() {
            assertEquals("user-1",
                    client.queries.fetchUserAndPost("user-1", "post-1").getUser().getId());
        }

        @Test
        void user_hasCorrectName() {
            assertEquals("Alice Smith",
                    client.queries.fetchUserAndPost("user-1", "post-1").getUser().getName());
        }

        @Test
        void post_isNotNull() {
            assertNotNull(client.queries.fetchUserAndPost("user-1", "post-1").getPost());
        }

        @Test
        void post_hasCorrectId() {
            assertEquals("post-1",
                    client.queries.fetchUserAndPost("user-1", "post-1").getPost().getId());
        }

        @Test
        void post_hasCorrectTitle() {
            assertEquals("Hello World",
                    client.queries.fetchUserAndPost("user-1", "post-1").getPost().getTitle());
        }

        @Test
        void post_author_hasCorrectId() {
            assertEquals("user-1",
                    client.queries.fetchUserAndPost("user-1", "post-1").getPost().getAuthor().getId());
        }

        @Test
        void singleAdapterCall_forBothResolvers() {
            client.queries.fetchUserAndPost("user-1", "post-1");
            assertEquals(1, adapter.getCallCount());
        }
    }

    // ── fetchUserSummary — partial projection ─────────────────────────────────

    @Nested
    class FetchUserSummary {

        @BeforeEach
        void register() {
            adapter.registerData("fetchUserSummary", Map.of(
                    "getUser", map("id", "user-1", "name", "Alice Smith", "status", "ACTIVE")
            ));
        }

        @Test
        void response_isNotNull() {
            assertNotNull(client.queries.fetchUserSummary("user-1"));
        }

        @Test
        void getUser_isNotNull() {
            assertNotNull(client.queries.fetchUserSummary("user-1").getGetUser());
        }

        @Test
        void getUser_isProjectedType() {
            assertInstanceOf(User_IdNameStatus.class,
                    client.queries.fetchUserSummary("user-1").getGetUser());
        }

        @Test
        void getUser_hasCorrectId() {
            assertEquals("user-1",
                    client.queries.fetchUserSummary("user-1").getGetUser().getId());
        }

        @Test
        void getUser_hasCorrectName() {
            assertEquals("Alice Smith",
                    client.queries.fetchUserSummary("user-1").getGetUser().getName());
        }

        @Test
        void getUser_status_deserializesToEnum() {
            assertEquals(UserStatus.ACTIVE,
                    client.queries.fetchUserSummary("user-1").getGetUser().getStatus());
        }
    }

    // ── runSearch — interface dispatch via __typename ─────────────────────────

    @Nested
    class RunSearch {

        @Test
        void userResult_dispatchedCorrectly() {
            adapter.registerData("runSearch", Map.of(
                    "search", List.of(
                            map("__typename", "UserResult", "id", "u-1",
                                "name", "Alice", "email", "alice@test.com")
                    )
            ));
            List<SearchResult> results = client.queries.runSearch("alice").getSearch();
            assertEquals(1, results.size());
            assertInstanceOf(UserResult.class, results.get(0));
            assertEquals("u-1", results.get(0).getId());
            assertEquals("Alice", ((UserResult) results.get(0)).getName());
        }

        @Test
        void postResult_dispatchedCorrectly() {
            adapter.registerData("runSearch", Map.of(
                    "search", List.of(
                            map("__typename", "PostResult", "id", "p-1", "title", "Hello")
                    )
            ));
            List<SearchResult> results = client.queries.runSearch("hello").getSearch();
            assertEquals(1, results.size());
            assertInstanceOf(PostResult.class, results.get(0));
            assertEquals("p-1", results.get(0).getId());
            assertEquals("Hello", ((PostResult) results.get(0)).getTitle());
        }

        @Test
        void mixedResults_dispatchedByTypename() {
            adapter.registerData("runSearch", Map.of(
                    "search", List.of(
                            map("__typename", "UserResult", "id", "u-1",
                                "name", "Alice", "email", "alice@test.com"),
                            map("__typename", "PostResult", "id", "p-1", "title", "Hello")
                    )
            ));
            List<SearchResult> results = client.queries.runSearch("a").getSearch();
            assertEquals(2, results.size());
            assertInstanceOf(UserResult.class, results.get(0));
            assertInstanceOf(PostResult.class, results.get(1));
        }

        @Test
        void emptyResults_returnEmptyList() {
            adapter.registerData("runSearch", Map.of("search", List.of()));
            List<SearchResult> results = client.queries.runSearch("xyz").getSearch();
            assertNotNull(results);
            assertTrue(results.isEmpty());
        }
    }

    // ── fetchCachedPair — cached multi-resolver query ─────────────────────────

    @Nested
    class FetchCachedPair {

        @BeforeEach
        void register() {
            adapter.registerData("fetchCachedPair", map(
                    "user", kUserAliceJson,
                    "post", kPostJson
            ));
        }

        @Test
        void firstCall_hitsAdapter() {
            client.queries.fetchCachedPair("user-1", "post-1");
            assertEquals(1, adapter.getCallCount());
        }

        @Test
        void secondCall_servedFromCache() {
            client.queries.fetchCachedPair("user-1", "post-1");
            client.queries.fetchCachedPair("user-1", "post-1");
            assertEquals(1, adapter.getCallCount());
        }

        @Test
        void cachedResponse_user_hasCorrectId() {
            client.queries.fetchCachedPair("user-1", "post-1");
            FetchCachedPairResponse res = client.queries.fetchCachedPair("user-1", "post-1");
            assertEquals("user-1", res.getUser().getId());
        }

        @Test
        void cachedResponse_post_hasCorrectId() {
            client.queries.fetchCachedPair("user-1", "post-1");
            FetchCachedPairResponse res = client.queries.fetchCachedPair("user-1", "post-1");
            assertEquals("post-1", res.getPost().getId());
        }

        @Test
        void differentArgs_bypassCache() {
            adapter.registerData("fetchCachedPair", map("user", kUserBobJson, "post", kPostJson));
            client.queries.fetchCachedPair("user-1", "post-1");
            client.queries.fetchCachedPair("user-2", "post-1");
            assertEquals(2, adapter.getCallCount());
        }
    }
}
