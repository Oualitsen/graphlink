package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.enums.Priority;
import dev.graphlink.test.generated.enums.UserStatus;
import dev.graphlink.test.generated.types.GetUserResponse;
import dev.graphlink.test.generated.types.ListUsersByStatusResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class EnumsTest {

    private MockAdapter adapter;
    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        adapter = new MockAdapter();
        client = newClient(adapter, new MockWebSocketAdapter());
    }

    // ── Enum deserialization in response ──────────────────────────────────────

    @Nested
    class EnumDeserialization {

        @Test
        void status_deserializesToUserStatus_ACTIVE() {
            adapter.registerData("getUser", Map.of("getUser", kUserAliceJson));
            GetUserResponse res = client.queries.getUser("user-1");
            assertInstanceOf(UserStatus.class, res.getGetUser().getStatus());
            assertEquals(UserStatus.ACTIVE, res.getGetUser().getStatus());
        }

        @Test
        void status_deserializesToUserStatus_INACTIVE() {
            adapter.registerData("getUser", Map.of("getUser", kUserBobJson));
            assertEquals(UserStatus.INACTIVE, client.queries.getUser("user-2").getGetUser().getStatus());
        }

        @Test
        void priority_deserializesToPriority_HIGH() {
            adapter.registerData("getUser", Map.of("getUser", kUserAliceJson));
            assertInstanceOf(Priority.class, client.queries.getUser("user-1").getGetUser().getPriority());
            assertEquals(Priority.HIGH, client.queries.getUser("user-1").getGetUser().getPriority());
        }

        @Test
        void priority_isNull_whenAbsent() {
            adapter.registerData("getUser", Map.of("getUser", kUserBobJson));
            assertNull(client.queries.getUser("user-2").getGetUser().getPriority());
        }
    }

    // ── Enum as query argument ─────────────────────────────────────────────────

    @Nested
    class EnumAsQueryArgument {

        @BeforeEach
        void register() {
            adapter.registerData("listUsersByStatus", Map.of("listUsersByStatus", List.of(kUserAliceJson)));
        }

        @Test
        void enumArg_isSentAsStringInVariables() {
            client.queries.listUsersByStatus(UserStatus.ACTIVE);
            assertEquals("ACTIVE", adapter.getLastCall().variables().get("status"));
        }

        @Test
        void operationName_isListUsersByStatus() {
            client.queries.listUsersByStatus(UserStatus.ACTIVE);
            assertEquals("listUsersByStatus", adapter.getLastCall().operationName());
        }

        @Test
        void response_containsDeserializedUsers() {
            ListUsersByStatusResponse res = client.queries.listUsersByStatus(UserStatus.ACTIVE);
            assertNotNull(res.getListUsersByStatus());
            assertEquals(1, res.getListUsersByStatus().size());
            assertEquals(UserStatus.ACTIVE, res.getListUsersByStatus().get(0).getStatus());
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
