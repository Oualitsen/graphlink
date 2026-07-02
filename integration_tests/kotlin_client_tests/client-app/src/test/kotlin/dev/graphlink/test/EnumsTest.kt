package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.Priority
import dev.graphlink.test.generated.enums.UserStatus
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.kUserAliceJson
import dev.graphlink.test.Fixtures.kUserBobJson
import dev.graphlink.test.Fixtures.newClient

class EnumsTest {

    private lateinit var adapter: MockAdapter
    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        adapter = MockAdapter()
        client = newClient(adapter, MockWebSocketAdapter())
    }

    // ── Enum deserialization in response ──────────────────────────────────────

    @Nested
    inner class EnumDeserialization {

        @Test
        fun status_deserializesToUserStatus_ACTIVE() = runTest {
            adapter.registerData("getUser", mapOf("getUser" to kUserAliceJson))
            val res = client.queries.getUser("user-1")
            assertIs<UserStatus>(res.getUser.status)
            assertEquals(UserStatus.ACTIVE, res.getUser.status)
        }

        @Test
        fun status_deserializesToUserStatus_INACTIVE() = runTest {
            adapter.registerData("getUser", mapOf("getUser" to kUserBobJson))
            assertEquals(UserStatus.INACTIVE, client.queries.getUser("user-2").getUser.status)
        }

        @Test
        fun priority_deserializesToPriority_HIGH() = runTest {
            adapter.registerData("getUser", mapOf("getUser" to kUserAliceJson))
            val priority = client.queries.getUser("user-1").getUser.priority
            assertIs<Priority>(priority)
            assertEquals(Priority.HIGH, priority)
        }

        @Test
        fun priority_isNull_whenAbsent() = runTest {
            adapter.registerData("getUser", mapOf("getUser" to kUserBobJson))
            assertNull(client.queries.getUser("user-2").getUser.priority)
        }
    }

    // ── Enum as query argument ────────────────────────────────────────────────

    @Nested
    inner class EnumAsQueryArgument {

        @BeforeTest
        fun register() {
            adapter.registerData("listUsersByStatus", mapOf("listUsersByStatus" to listOf(kUserAliceJson)))
        }

        @Test
        fun enumArg_isSentAsStringInVariables() = runTest {
            client.queries.listUsersByStatus(UserStatus.ACTIVE)
            assertEquals("ACTIVE", adapter.getLastCall()?.variables?.get("status"))
        }

        @Test
        fun operationName_isListUsersByStatus() = runTest {
            client.queries.listUsersByStatus(UserStatus.ACTIVE)
            assertEquals("listUsersByStatus", adapter.getLastCall()?.operationName)
        }

        @Test
        fun response_containsDeserializedUsers() = runTest {
            val res = client.queries.listUsersByStatus(UserStatus.ACTIVE)
            assertNotNull(res.listUsersByStatus)
            assertEquals(1, res.listUsersByStatus.size)
            assertEquals(UserStatus.ACTIVE, res.listUsersByStatus[0].status)
        }
    }

    // ── All enum values round-trip ────────────────────────────────────────────

    @Nested
    inner class EnumRoundTrip {

        @Test
        fun userStatus_ACTIVE_roundTrips() {
            assertEquals("ACTIVE", UserStatus.ACTIVE.toJson())
            assertEquals(UserStatus.ACTIVE, UserStatus.fromJson("ACTIVE"))
        }

        @Test
        fun userStatus_INACTIVE_roundTrips() {
            assertEquals("INACTIVE", UserStatus.INACTIVE.toJson())
            assertEquals(UserStatus.INACTIVE, UserStatus.fromJson("INACTIVE"))
        }

        @Test
        fun userStatus_SUSPENDED_roundTrips() {
            assertEquals("SUSPENDED", UserStatus.SUSPENDED.toJson())
            assertEquals(UserStatus.SUSPENDED, UserStatus.fromJson("SUSPENDED"))
        }

        @Test
        fun priority_LOW_roundTrips() {
            assertEquals("LOW", Priority.LOW.toJson())
            assertEquals(Priority.LOW, Priority.fromJson("LOW"))
        }

        @Test
        fun priority_CRITICAL_roundTrips() {
            assertEquals("CRITICAL", Priority.CRITICAL.toJson())
            assertEquals(Priority.CRITICAL, Priority.fromJson("CRITICAL"))
        }

    }
}
