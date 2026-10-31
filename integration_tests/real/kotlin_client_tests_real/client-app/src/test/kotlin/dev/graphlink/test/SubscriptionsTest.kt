package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec
import dev.graphlink.test.generated.enums.UserStatus
import dev.graphlink.test.generated.types.UserCreatedResponse
import dev.graphlink.test.generated.types.UserStatusChangedResponse
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import dev.graphlink.test.generated.types.UserCreatedsResponse
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.SERVER_URL
import dev.graphlink.test.Fixtures.WS_URL
import dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter

class SubscriptionsTest {

    private lateinit var wsAdapter: DefaultGraphLinkWebSocketAdapter
    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        val codec = KotlinxSerializationGraphLinkJsonCodec()
        wsAdapter = DefaultGraphLinkWebSocketAdapter(WS_URL)
        client = GraphLinkClient(
            OkHttpGraphLinkClientAdapter(SERVER_URL),
            wsAdapter,
            MockMultipartAdapter(),
            codec, codec,
        )
    }

    @AfterTest
    fun tearDown() {
        wsAdapter.close()
    }

    // ── userCreated ────────────────────────────────────────────────────────────

    @Nested
    inner class UserCreated {

        @Test
        fun firstEvent_isAlice() = runTest {
            val events: List<UserCreatedResponse> = client.subscriptions.userCreated().take(1).toList()
            assertEquals("user-1", events[0].userCreated.id)
        }

        @Test
        fun firstEvent_name_isAliceSmith() = runTest {
            val events = client.subscriptions.userCreated().take(1).toList()
            assertEquals("Alice Smith", events[0].userCreated.name)
        }

        @Test
        fun firstEvent_status_deserializesToEnum() = runTest {
            val events = client.subscriptions.userCreated().take(1).toList()
            assertEquals(UserStatus.ACTIVE, events[0].userCreated.status)
        }

        @Test
        fun bothEvents_deliveredInOrder() = runTest {
            val events = client.subscriptions.userCreated().take(2).toList()
            assertEquals(2, events.size)
            assertEquals("user-1", events[0].userCreated.id)
            assertEquals("user-2", events[1].userCreated.id)
        }
    }

    // ── MultipleIdenticalSubscriptions ────────────────────────────────────────
    // Same operation + same args collected concurrently via async — each call
    // gets its own UUID so both flows receive independent events from the server.

    @Nested
    inner class MultipleIdenticalSubscriptions {

        @Test
        fun userCreated_registeredTwice_bothReceiveAllEvents() = runTest {
            val deferred1 = async { client.subscriptions.userCreated().take(2).toList() }
            val deferred2 = async { client.subscriptions.userCreated().take(2).toList() }

            val events1 = deferred1.await()
            val events2 = deferred2.await()

            assertEquals(2, events1.size)
            assertEquals("user-1", events1[0].userCreated.id)
            assertEquals("user-2", events1[1].userCreated.id)
            assertEquals(2, events2.size)
            assertEquals("user-1", events2[0].userCreated.id)
            assertEquals("user-2", events2[1].userCreated.id)
        }

        @Test
        fun userStatusChanged_sameArg_registeredTwice_bothReceiveEvent() = runTest {
            val deferred1 = async { client.subscriptions.userStatusChanged("user-1").take(1).toList() }
            val deferred2 = async { client.subscriptions.userStatusChanged("user-1").take(1).toList() }

            val events1 = deferred1.await()
            val events2 = deferred2.await()

            assertEquals("user-1", events1[0].userStatusChanged.id)
            assertEquals(UserStatus.ACTIVE, events1[0].userStatusChanged.status)
            assertEquals("user-1", events2[0].userStatusChanged.id)
            assertEquals(UserStatus.ACTIVE, events2[0].userStatusChanged.status)
        }
    }

    // ── MultipleDifferentSubscriptions ────────────────────────────────────────
    // Different operations or same operation with different args — verifies that
    // UUID routing delivers each event only to the correct collector.

    @Nested
    inner class MultipleDifferentSubscriptions {

        @Test
        fun userCreated_and_userStatusChanged_runConcurrently() = runTest {
            val deferred1 = async { client.subscriptions.userCreated().take(1).toList() }
            val deferred2 = async { client.subscriptions.userStatusChanged("user-1").take(1).toList() }

            val userCreatedEvents = deferred1.await()
            val statusEvents = deferred2.await()

            assertEquals("user-1", userCreatedEvents[0].userCreated.id)
            assertEquals("user-1", statusEvents[0].userStatusChanged.id)
            assertEquals(UserStatus.ACTIVE, statusEvents[0].userStatusChanged.status)
        }

        @Test
        fun userStatusChanged_differentArgs_receiveIndependentEvents() = runTest {
            val deferred1 = async { client.subscriptions.userStatusChanged("user-1").take(1).toList() }
            val deferred2 = async { client.subscriptions.userStatusChanged("user-2").take(1).toList() }

            val events1 = deferred1.await()
            val events2 = deferred2.await()

            assertEquals("user-1", events1[0].userStatusChanged.id)
            assertEquals(UserStatus.ACTIVE, events1[0].userStatusChanged.status)
            assertEquals("user-2", events2[0].userStatusChanged.id)
            assertEquals(UserStatus.INACTIVE, events2[0].userStatusChanged.status)
        }

        @Test
        fun userCreated_and_userCreateds_runConcurrently() = runTest {
            val deferred1 = async { client.subscriptions.userCreated().take(1).toList() }
            val deferred2 = async { client.subscriptions.userCreateds(listOf("user-1", "user-2")).take(1).toList() }

            val singleEvents = deferred1.await()
            val listEvents = deferred2.await()

            assertEquals("user-1", singleEvents[0].userCreated.id)
            assertNotNull(listEvents[0].userCreateds)
            assertEquals(2, listEvents[0].userCreateds!!.size)
            assertEquals("user-1", listEvents[0].userCreateds!![0].id)
            assertEquals("user-2", listEvents[0].userCreateds!![1].id)
        }
    }

    // ── userStatusChanged ──────────────────────────────────────────────────────

    @Nested
    inner class UserStatusChanged {

        @Test
        fun event_returnsCorrectUser() = runTest {
            val events: List<UserStatusChangedResponse> =
                client.subscriptions.userStatusChanged("user-1").take(1).toList()
            assertEquals("user-1", events[0].userStatusChanged.id)
        }

        @Test
        fun event_status_isCorrect() = runTest {
            val events = client.subscriptions.userStatusChanged("user-1").take(1).toList()
            assertEquals(UserStatus.ACTIVE, events[0].userStatusChanged.status)
        }
    }
}
