package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.enums.UserStatus;
import dev.graphlink.test.generated.types.Address;
import dev.graphlink.test.generated.types.AuditEntry;
import dev.graphlink.test.generated.types.GetAuditEntryResponse;
import dev.graphlink.test.generated.types.GetPostResponse;
import dev.graphlink.test.generated.types.GetUserResponse;
import dev.graphlink.test.generated.types.Post;
import dev.graphlink.test.generated.types.User;
import dev.graphlink.test.generated.types.User_AddressBillingAddressEmail_aep45g;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class NestedTypesTest {

    private MockAdapter adapter;
    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        adapter = new MockAdapter();
        client = newClient(adapter, new MockWebSocketAdapter());
    }

    // ── Required nested object (User.address) ─────────────────────────────────

    @Nested
    class RequiredNestedObject {

        @BeforeEach
        void register() {
            adapter.registerData("getUser", Map.of("getUser", kUserAliceJson));
        }

        @Test
        void address_isNotNull() {
            assertNotNull(client.queries.getUser("user-1").getGetUser().getAddress());
        }

        @Test
        void address_hasCorrectStreet() {
            assertEquals("123 Main St",
                    client.queries.getUser("user-1").getGetUser().getAddress().getStreet());
        }

        @Test
        void address_hasCorrectCity() {
            assertEquals("Springfield",
                    client.queries.getUser("user-1").getGetUser().getAddress().getCity());
        }

        @Test
        void address_hasCorrectCountry() {
            assertEquals("US",
                    client.queries.getUser("user-1").getGetUser().getAddress().getCountry());
        }

        @Test
        void address_hasCorrectZip() {
            assertEquals("12345",
                    client.queries.getUser("user-1").getGetUser().getAddress().getZip());
        }

        @Test
        void address_deserializesToAddressType() {
            assertInstanceOf(Address.class,
                    client.queries.getUser("user-1").getGetUser().getAddress());
        }
    }

    // ── Post with required author (multi-level nesting) ───────────────────────

    @Nested
    class MultiLevelNesting {

        @BeforeEach
        void register() {
            adapter.registerData("getPost", Map.of("getPost", kPostJson));
        }

        @Test
        void post_isNotNull() {
            assertNotNull(client.queries.getPost("post-1").getGetPost());
        }

        @Test
        void post_deserializesToPostType() {
            assertInstanceOf(Post.class, client.queries.getPost("post-1").getGetPost());
        }

        @Test
        void post_hasCorrectTitle() {
            assertEquals("Hello World",
                    client.queries.getPost("post-1").getGetPost().getTitle());
        }

        @Test
        void post_author_isNotNull() {
            assertNotNull(client.queries.getPost("post-1").getGetPost().getAuthor());
        }

        @Test
        void post_author_deserializesToUserFragmentType() {
            assertInstanceOf(User_AddressBillingAddressEmail_aep45g.class,
                    client.queries.getPost("post-1").getGetPost().getAuthor());
        }

        @Test
        void post_author_hasCorrectId() {
            assertEquals("user-1",
                    client.queries.getPost("post-1").getGetPost().getAuthor().getId());
        }

        @Test
        void post_author_status_deserializesToEnum() {
            assertEquals(UserStatus.ACTIVE,
                    client.queries.getPost("post-1").getGetPost().getAuthor().getStatus());
        }

        @Test
        void post_author_address_city_isAccessible() {
            assertEquals("Springfield",
                    client.queries.getPost("post-1").getGetPost().getAuthor().getAddress().getCity());
        }

        @Test
        void post_viewCount_deserializesToInteger() {
            assertEquals(128, client.queries.getPost("post-1").getGetPost().getViewCount());
        }
    }

    // ── @glSkipOnClient — server-only field silently ignored ──────────────────

    @Nested
    class SkipOnClientField {

        @Test
        void auditEntry_withoutInternalNote_deserializesCorrectly() {
            adapter.registerData("getAuditEntry", Map.of("getAuditEntry", kAuditEntryJson));
            GetAuditEntryResponse res = client.queries.getAuditEntry("audit-1");
            AuditEntry entry = res.getGetAuditEntry();
            assertNotNull(entry);
            assertEquals("audit-1", entry.getId());
            assertEquals("LOGIN", entry.getAction());
            assertEquals("user-1", entry.getPerformedBy());
        }

        @Test
        void auditEntry_withExtraServerField_isIgnoredSilently() {
            adapter.registerData("getAuditEntry", Map.of("getAuditEntry", kAuditEntryWithExtraJson));
            GetAuditEntryResponse res = client.queries.getAuditEntry("audit-2");
            AuditEntry entry = res.getGetAuditEntry();
            assertNotNull(entry);
            assertEquals("audit-2", entry.getId());
            assertEquals("LOGOUT", entry.getAction());
        }
    }
}
