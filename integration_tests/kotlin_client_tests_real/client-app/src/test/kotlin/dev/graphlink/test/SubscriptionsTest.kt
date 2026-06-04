package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec
import dev.graphlink.test.generated.enums.UserStatus
import dev.graphlink.test.generated.types.UserCreatedResponse
import dev.graphlink.test.generated.types.UserStatusChangedResponse
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.SERVER_URL
import dev.graphlink.test.Fixtures.WS_URL

class SubscriptionsTest {

    private lateinit var wsAdapter: OkHttpGraphLinkWebSocketAdapter
    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        val codec = KotlinxSerializationGraphLinkJsonCodec()
        wsAdapter = OkHttpGraphLinkWebSocketAdapter(WS_URL)
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
