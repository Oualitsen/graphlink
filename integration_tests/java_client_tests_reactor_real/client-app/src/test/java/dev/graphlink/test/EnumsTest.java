package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.enums.Priority;
import dev.graphlink.test.generated.enums.UserStatus;
import dev.graphlink.test.generated.types.GetUserResponse;
import dev.graphlink.test.generated.types.ListUsersByStatusResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class EnumsTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    // ── Enum deserialization in response ──────────────────────────────────────

    @Nested
    class EnumDeserialization {

        @Test
        void status_deserializesToUserStatus_ACTIVE() {
            GetUserResponse res = client.queries.getUser("user-1").block();
            assertInstanceOf(UserStatus.class, res.getGetUser().getStatus());
            assertEquals(UserStatus.ACTIVE, res.getGetUser().getStatus());
        }

        @Test
        void status_deserializesToUserStatus_INACTIVE() {
            assertEquals(UserStatus.INACTIVE, client.queries.getUser("user-2").block().getGetUser().getStatus());
        }

        @Test
        void priority_deserializesToPriority_HIGH() {
            assertInstanceOf(Priority.class, client.queries.getUser("user-1").block().getGetUser().getPriority());
            assertEquals(Priority.HIGH, client.queries.getUser("user-1").block().getGetUser().getPriority());
        }

        @Test
        void priority_isNull_forBob() {
            assertNull(client.queries.getUser("user-2").block().getGetUser().getPriority());
        }
    }

    // ── Enum as query argument ────────────────────────────────────────────────

    @Nested
    class EnumAsQueryArgument {

        @Test
        void listUsersByStatus_ACTIVE_returnsOnlyActiveUsers() {
            ListUsersByStatusResponse res = client.queries.listUsersByStatus(UserStatus.ACTIVE).block();
            assertNotNull(res.getListUsersByStatus());
            assertFalse(res.getListUsersByStatus().isEmpty());
            res.getListUsersByStatus().forEach(u ->
                    assertEquals(UserStatus.ACTIVE, u.getStatus()));
        }

        @Test
        void listUsersByStatus_INACTIVE_returnsOnlyInactiveUsers() {
            ListUsersByStatusResponse res = client.queries.listUsersByStatus(UserStatus.INACTIVE).block();
            assertNotNull(res.getListUsersByStatus());
            assertFalse(res.getListUsersByStatus().isEmpty());
            res.getListUsersByStatus().forEach(u ->
                    assertEquals(UserStatus.INACTIVE, u.getStatus()));
        }
    }

    // ── All enum values round-trip ────────────────────────────────────────────

    @Nested
    class EnumRoundTrip {

        @Test
        void userStatus_ACTIVE_roundTrips() {
            assertEquals("ACTIVE", UserStatus.ACTIVE.toJson());
            assertEquals(UserStatus.ACTIVE, UserStatus.fromJson("ACTIVE"));
        }

        @Test
        void userStatus_INACTIVE_roundTrips() {
            assertEquals("INACTIVE", UserStatus.INACTIVE.toJson());
            assertEquals(UserStatus.INACTIVE, UserStatus.fromJson("INACTIVE"));
        }

        @Test
        void userStatus_SUSPENDED_roundTrips() {
            assertEquals("SUSPENDED", UserStatus.SUSPENDED.toJson());
            assertEquals(UserStatus.SUSPENDED, UserStatus.fromJson("SUSPENDED"));
        }

        @Test
        void priority_LOW_roundTrips() {
            assertEquals("LOW", Priority.LOW.toJson());
            assertEquals(Priority.LOW, Priority.fromJson("LOW"));
        }

        @Test
        void priority_CRITICAL_roundTrips() {
            assertEquals("CRITICAL", Priority.CRITICAL.toJson());
            assertEquals(Priority.CRITICAL, Priority.fromJson("CRITICAL"));
        }

        @Test
        void fromJson_null_returnsNull() {
            assertNull(UserStatus.fromJson(null));
            assertNull(Priority.fromJson(null));
        }
    }
}
