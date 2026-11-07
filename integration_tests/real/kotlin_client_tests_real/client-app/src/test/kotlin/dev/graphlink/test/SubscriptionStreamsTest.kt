package dev.graphlink.test

import dev.graphlink.test.Fixtures.SERVER_URL
import dev.graphlink.test.Fixtures.WS_URL
import dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec
import dev.graphlink.test.generated.enums.OnlyOne
import dev.graphlink.test.generated.enums.Spelling
import dev.graphlink.test.generated.inputs.ListsInput
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import kotlin.test.*

class SubscriptionStreamsTest {

    private lateinit var wsAdapter: DefaultGraphLinkWebSocketAdapter
    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        val codec = KotlinxSerializationGraphLinkJsonCodec()
        wsAdapter = DefaultGraphLinkWebSocketAdapter(WS_URL)
        client = GraphLinkClient(OkHttpGraphLinkClientAdapter(SERVER_URL), wsAdapter, MockMultipartAdapter(), codec, codec)
    }

    @AfterTest
    fun tearDown() {
        wsAdapter.close()
    }

    private suspend fun <T> drain(flow: Flow<T>): Pair<List<T>, Throwable?> {
        val events = mutableListOf<T>()
        var error: Throwable? = null
        flow.catch { error = it }.collect { events.add(it) }
        return events to error
    }

    @Test
    fun everyArgumentShapeRoundTrips() = runTest {
        val (events, error) = drain(
            client.subscriptions.subEchoArgs(
                a = listOf(1, 2), b = listOf(1, null), c = listOf(listOf(1), listOf(), listOf(2, 3)),
                e = listOf(Spelling.X_Y, Spelling.HTTP2_OK), f = listOf(null, Spelling.V1),
            )
        )
        assertNull(error)
        assertEquals(1, events.size)
        val r = events[0].subEchoArgs
        assertEquals(listOf(1, 2), r.a)
        assertEquals(listOf(1, null), r.b)
        assertEquals(listOf(listOf(1), listOf(), listOf(2, 3)), r.c)
        assertEquals(listOf(Spelling.X_Y, Spelling.HTTP2_OK), r.e)
        assertEquals(listOf(null, Spelling.V1), r.f)
    }

    @Test
    fun omittedArgumentsAreNullAndDefaultsApply() = runTest {
        val r = drain(client.subscriptions.subEchoArgs(a = listOf(), e = listOf())).first[0].subEchoArgs
        assertNull(r.b)
        assertNull(r.c)
        assertNull(r.f)
        assertEquals(listOf(Spelling.A, Spelling.B2), r.g)
        assertEquals(OnlyOne.ONLY, r.one)
    }

    @Test
    fun inputObjectRoundTrips() = runTest {
        val input = ListsInput(
            a = listOf(3, 4), b = listOf(null, 5), c = listOf(listOf(1, 2), listOf()),
            e = listOf(Spelling.SNAKE_CASE_2), f = listOf(Spelling.A, null), g = listOf(Spelling.V1),
        )
        val r = drain(client.subscriptions.subEchoInput(input)).first[0].subEchoInput
        assertEquals(listOf(3, 4), r.a)
        assertEquals(listOf(null, 5), r.b)
        assertEquals(listOf(listOf(1, 2), listOf()), r.c)
        assertEquals(listOf(Spelling.SNAKE_CASE_2), r.e)
        assertEquals(listOf(Spelling.A, null), r.f)
        assertEquals(listOf(Spelling.V1), r.g)
    }

    @Test
    fun serverCompletionEndsTheFlow() = runTest {
        val (events, error) = drain(client.subscriptions.finiteTicks(5))
        assertNull(error)
        assertEquals(listOf(1, 2, 3, 4, 5), events.map { it.finiteTicks })
    }

    @Test
    fun completionWithoutEventsIsAnEmptyFlow() = runTest {
        val (events, error) = drain(client.subscriptions.finiteTicks(0))
        assertEquals(listOf(), events)
        assertNull(error)
    }

    @Test
    fun eventsBeforeTheFailureArriveThenTheError() = runTest {
        val (events, error) = drain(client.subscriptions.flakyTicks(3))
        assertEquals(listOf(1, 2, 3), events.map { it.flakyTicks })
        assertNotNull(error)
    }

    @Test
    fun failureBeforeTheFirstEvent() = runTest {
        val (events, error) = drain(client.subscriptions.flakyTicks(0))
        assertEquals(listOf(), events)
        assertNotNull(error)
    }

    @Test
    fun failedStreamDoesNotBreakTheNextSubscription() = runTest {
        drain(client.subscriptions.flakyTicks(1))
        val (events, error) = drain(client.subscriptions.finiteTicks(2))
        assertNull(error)
        assertEquals(2, events.size)
    }
}
