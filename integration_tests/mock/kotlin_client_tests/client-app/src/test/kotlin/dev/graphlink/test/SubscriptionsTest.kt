package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.UserStatus
import dev.graphlink.test.generated.types.UserCreatedResponse
import dev.graphlink.test.generated.types.UserStatusChangedResponse
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.kUserAliceJson
import dev.graphlink.test.Fixtures.kUserBobJson
import dev.graphlink.test.Fixtures.newClient

class SubscriptionsTest {

    private lateinit var adapter: MockAdapter
    private lateinit var wsAdapter: MockWebSocketAdapter
    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        adapter = MockAdapter()
        wsAdapter = MockWebSocketAdapter()
        client = newClient(adapter, wsAdapter)
    }

    // ── userCreated ────────────────────────────────────────────────────────────

    @Nested
    inner class UserCreated {

        @Test
        fun singleEvent_deserializedCorrectly() = runTest {
            val events = mutableListOf<UserCreatedResponse>()
            val job = launch { client.subscriptions.userCreated().collect { events += it } }
            advanceUntilIdle()

            wsAdapter.deliverConnectionAck()
            val subId = wsAdapter.getLastSubscriptionId()
            wsAdapter.deliverNext(subId, mapOf("userCreated" to kUserAliceJson))
            advanceUntilIdle()

            assertEquals(1, events.size)
            assertEquals("user-1", events[0].userCreated.id)
            job.cancel()
        }

        @Test
        fun singleEvent_name_isCorrect() = runTest {
            val events = mutableListOf<UserCreatedResponse>()
            val job = launch { client.subscriptions.userCreated().collect { events += it } }
            advanceUntilIdle()

            wsAdapter.deliverConnectionAck()
            val subId = wsAdapter.getLastSubscriptionId()
            wsAdapter.deliverNext(subId, mapOf("userCreated" to kUserAliceJson))
            advanceUntilIdle()

            assertEquals("Alice Smith", events[0].userCreated.name)
            job.cancel()
        }

        @Test
        fun singleEvent_status_deserializesToEnum() = runTest {
            val events = mutableListOf<UserCreatedResponse>()
            val job = launch { client.subscriptions.userCreated().collect { events += it } }
            advanceUntilIdle()

            wsAdapter.deliverConnectionAck()
            val subId = wsAdapter.getLastSubscriptionId()
            wsAdapter.deliverNext(subId, mapOf("userCreated" to kUserAliceJson))
            advanceUntilIdle()

            assertEquals(UserStatus.ACTIVE, events[0].userCreated.status)
            job.cancel()
        }

        @Test
        fun multipleEvents_deliveredInOrder() = runTest {
            val events = mutableListOf<UserCreatedResponse>()
            val job = launch { client.subscriptions.userCreated().collect { events += it } }
            advanceUntilIdle()

            wsAdapter.deliverConnectionAck()
            val subId = wsAdapter.getLastSubscriptionId()
            wsAdapter.deliverNext(subId, mapOf("userCreated" to kUserAliceJson))
            wsAdapter.deliverNext(subId, mapOf("userCreated" to kUserBobJson))
            advanceUntilIdle()

            assertEquals(2, events.size)
            assertEquals("user-1", events[0].userCreated.id)
            assertEquals("user-2", events[1].userCreated.id)
            job.cancel()
        }

        @Test
        fun connectionInit_isSent_firstMessage() = runTest {
            val job = launch { client.subscriptions.userCreated().collect {} }
            advanceUntilIdle()

            val first = wsAdapter.sentMessagesDecoded.firstOrNull()
            assertNotNull(first)
            assertEquals("connection_init", first["type"])
            job.cancel()
        }

        @Test
        fun subscribeMessage_isSent_afterConnectionAck() = runTest {
            val job = launch { client.subscriptions.userCreated().collect {} }
            advanceUntilIdle()

            wsAdapter.deliverConnectionAck()

            val subscribeCount = wsAdapter.sentMessagesDecoded.count { it["type"] == "subscribe" }
            assertEquals(1, subscribeCount)
            job.cancel()
        }
    }

    // ── userStatusChanged ──────────────────────────────────────────────────────

    @Nested
    inner class UserStatusChanged {

        @Test
        fun event_deserializedCorrectly() = runTest {
            val events = mutableListOf<UserStatusChangedResponse>()
            val job = launch {
                client.subscriptions.userStatusChanged("user-1").collect { events += it }
            }
            advanceUntilIdle()

            wsAdapter.deliverConnectionAck()
            val subId = wsAdapter.getLastSubscriptionId()
            wsAdapter.deliverNext(subId, mapOf("userStatusChanged" to kUserAliceJson))
            advanceUntilIdle()

            assertEquals(1, events.size)
            assertEquals("user-1", events[0].userStatusChanged.id)
            job.cancel()
        }

        @Test
        fun event_status_isCorrect() = runTest {
            val events = mutableListOf<UserStatusChangedResponse>()
            val job = launch {
                client.subscriptions.userStatusChanged("user-1").collect { events += it }
            }
            advanceUntilIdle()

            wsAdapter.deliverConnectionAck()
            val subId = wsAdapter.getLastSubscriptionId()
            wsAdapter.deliverNext(subId, mapOf("userStatusChanged" to kUserAliceJson))
            advanceUntilIdle()

            assertEquals(UserStatus.ACTIVE, events[0].userStatusChanged.status)
            job.cancel()
        }

        @Test
        fun userId_sentInSubscribePayload() = runTest {
            val job = launch {
                client.subscriptions.userStatusChanged("user-42").collect {}
            }
            advanceUntilIdle()
            wsAdapter.deliverConnectionAck()

            val subscribeMsg = wsAdapter.sentMessagesDecoded.first { it["type"] == "subscribe" }
            @Suppress("UNCHECKED_CAST")
            val payload = subscribeMsg["payload"] as Map<String, Any?>
            @Suppress("UNCHECKED_CAST")
            val variables = payload["variables"] as Map<String, Any?>
            assertEquals("user-42", variables["userId"])
            job.cancel()
        }
    }
}
