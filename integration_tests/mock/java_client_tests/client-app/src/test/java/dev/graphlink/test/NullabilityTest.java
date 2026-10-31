package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.types.FindUserResponse;
import dev.graphlink.test.generated.types.GetPostResponse;
import dev.graphlink.test.generated.types.GetUserResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class NullabilityTest {

    private MockAdapter adapter;
    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        adapter = new MockAdapter();
        client = newClient(adapter, new MockWebSocketAdapter());
    }

    // ── Non-nullable query return type ────────────────────────────────────────

    @Nested
    class NonNullableQueryReturn {

        @BeforeEach
        void register() {
            adapter.registerData("getUser", Map.of("getUser", kUserAliceJson));
        }

        @Test
        void getUser_returnsNonNullUser() {
            GetUserResponse res = client.queries.getUser("user-1");
            assertNotNull(res.getGetUser());
        }

        @Test
        void getUser_hasCorrectId() {
            assertEquals("user-1", client.queries.getUser("user-1").getGetUser().getId());
        }
    }

    // ── Nullable query return type — null ─────────────────────────────────────

    @Nested
    class NullableQueryReturn_Null {

        @BeforeEach
        void register() {
            adapter.registerData("findUser", map("findUser", null));
        }

        @Test
        void findUser_returnsNull_whenServerReturnsNull() {
            FindUserResponse res = client.queries.findUser("user-99");
            assertNull(res.getFindUser());
        }
    }

    // ── Nullable query return type — present ──────────────────────────────────

    @Nested
    class NullableQueryReturn_Present {

        @BeforeEach
        void register() {
            adapter.registerData("findUser", Map.of("findUser", kUserAliceJson));
        }

        @Test
        void findUser_returnsUser_whenServerReturnsData() {
            FindUserResponse res = client.queries.findUser("user-1");
            assertNotNull(res.getFindUser());
            assertEquals("user-1", res.getFindUser().getId());
        }
    }

    // ── Nullable nested object — null ─────────────────────────────────────────

    @Nested
    class NullableNestedObject_Null {

        @BeforeEach
        void register() {
            adapter.registerData("getUser", Map.of("getUser", kUserAliceJson));
        }

        @Test
        void billingAddress_isNull_whenAbsent() {
            assertNull(client.queries.getUser("user-1").getGetUser().getBillingAddress());
        }
    }

    // ── Nullable nested object — present ──────────────────────────────────────

    @Nested
    class NullableNestedObject_Present {

        @BeforeEach
        void register() {
            adapter.registerData("getUser", Map.of("getUser", kUserBobJson));
        }

        @Test
        void billingAddress_isNotNull_whenPresent() {
            assertNotNull(client.queries.getUser("user-2").getGetUser().getBillingAddress());
        }

        @Test
        void billingAddress_hasCorrectCity() {
            assertEquals("Capital City",
                    client.queries.getUser("user-2").getGetUser().getBillingAddress().getCity());
        }
    }

    // ── Nullable scalar on nested type ────────────────────────────────────────

    @Nested
    class NullableScalarOnNestedType {

        @Test
        void address_zip_isNull_whenAbsent() {
            adapter.registerData("getUser", Map.of("getUser", kUserBobJson));
            assertNull(client.queries.getUser("user-2").getGetUser().getAddress().getZip());
        }

        @Test
        void address_zip_isPresent_whenSet() {
            adapter.registerData("getUser", Map.of("getUser", kUserAliceJson));
            assertEquals("12345",
                    client.queries.getUser("user-1").getGetUser().getAddress().getZip());
        }
    }

    // ── Nullable list field ───────────────────────────────────────────────────

    @Nested
    class NullableListField {

        @Test
        void scores_isNull_whenAbsent() {
            adapter.registerData("getUser", Map.of("getUser", kUserBobJson));
            assertNull(client.queries.getUser("user-2").getGetUser().getScores());
        }

        @Test
        void scores_hasList_whenPresent() {
            adapter.registerData("getUser", Map.of("getUser", kUserAliceJson));
            assertNotNull(client.queries.getUser("user-1").getGetUser().getScores());
            assertEquals(3, client.queries.getUser("user-1").getGetUser().getScores().size());
        }
    }

    // ── Nullable object on Post — coAuthor ────────────────────────────────────

    @Nested
    class NullableCoAuthor {

        @Test
        void coAuthor_isNull_whenAbsent() {
            adapter.registerData("getPost", Map.of("getPost", kPostJson));
            assertNull(client.queries.getPost("post-1").getGetPost().getCoAuthor());
        }

        @Test
        void coAuthor_isNotNull_whenPresent() {
            adapter.registerData("getPost", Map.of("getPost", kPostWithCoAuthorJson));
            assertNotNull(client.queries.getPost("post-2").getGetPost().getCoAuthor());
            assertEquals("user-2",
                    client.queries.getPost("post-2").getGetPost().getCoAuthor().getId());
        }
    }
}
