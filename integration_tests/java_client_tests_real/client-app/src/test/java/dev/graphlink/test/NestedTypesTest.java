package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.enums.UserStatus;
import dev.graphlink.test.generated.types.*;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class NestedTypesTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    // ── Required nested object (User.address) ─────────────────────────────────

    @Nested
    class RequiredNestedObject {

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
            assertInstanceOf(User.class,
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
        void auditEntry_deserializesCorrectly() {
            GetAuditEntryResponse res = client.queries.getAuditEntry("audit-1");
            AuditEntry entry = res.getGetAuditEntry();
            assertNotNull(entry);
            assertEquals("audit-1", entry.getId());
            assertEquals("LOGIN", entry.getAction());
            assertEquals("user-1", entry.getPerformedBy());
        }

        @Test
        void auditEntry_withServerOnlyField_isIgnoredSilently() {
            GetAuditEntryResponse res = client.queries.getAuditEntry("audit-2");
            AuditEntry entry = res.getGetAuditEntry();
            assertNotNull(entry);
            assertEquals("audit-2", entry.getId());
            assertEquals("LOGOUT", entry.getAction());
        }
    }
}
