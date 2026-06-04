package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.enums.UserStatus;
import dev.graphlink.test.generated.interfaces.SearchResult;
import dev.graphlink.test.generated.types.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.List;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class CustomQueriesTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    // ── fetchUserAndPost — multi-resolver, single round-trip ──────────────────

    @Nested
    class FetchUserAndPost {

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
    }

    // ── fetchUserSummary — partial projection ─────────────────────────────────

    @Nested
    class FetchUserSummary {

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
        void results_containUserResult() {
            List<SearchResult> results = client.queries.runSearch("alice").getSearch();
            assertNotNull(results);
            assertTrue(results.stream().anyMatch(r -> r instanceof UserResult));
        }

        @Test
        void results_containPostResult() {
            List<SearchResult> results = client.queries.runSearch("alice").getSearch();
            assertNotNull(results);
            assertTrue(results.stream().anyMatch(r -> r instanceof PostResult));
        }

        @Test
        void userResult_hasCorrectId() {
            List<SearchResult> results = client.queries.runSearch("alice").getSearch();
            UserResult user = results.stream()
                    .filter(r -> r instanceof UserResult)
                    .map(r -> (UserResult) r)
                    .findFirst().orElseThrow();
            assertEquals("user-1", user.getId());
            assertEquals("Alice Smith", user.getName());
        }

        @Test
        void postResult_hasCorrectId() {
            List<SearchResult> results = client.queries.runSearch("alice").getSearch();
            PostResult post = results.stream()
                    .filter(r -> r instanceof PostResult)
                    .map(r -> (PostResult) r)
                    .findFirst().orElseThrow();
            assertEquals("post-1", post.getId());
        }
    }
}
