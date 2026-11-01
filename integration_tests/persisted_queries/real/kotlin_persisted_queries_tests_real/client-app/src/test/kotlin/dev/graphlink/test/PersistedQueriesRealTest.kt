package dev.graphlink.test

import dev.graphlink.test.generated.client.DefaultGraphLinkClientAdapter
import dev.graphlink.test.generated.client.DefaultGraphLinkGetAdapter
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec
import dev.graphlink.test.generated.enums.UserStatus
import dev.graphlink.test.generated.inputs.AddressInput
import dev.graphlink.test.generated.inputs.CreateUserInput
import kotlinx.coroutines.test.runTest
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import kotlin.test.*

class PersistedQueriesRealTest {
    private val codec = KotlinxSerializationGraphLinkJsonCodec()
    private lateinit var client: GraphLinkClient

    private val newUser = CreateUserInput(
        name = "Persisted Pat",
        email = "pat@test.com",
        status = UserStatus.ACTIVE,
        address = AddressInput("s", "c", "x"),
    )

    @Suppress("UNCHECKED_CAST")
    private fun control(method: String, path: String): Map<String, Any?> {
        val request = HttpRequest.newBuilder(URI.create("http://localhost:$PORT/test/apq$path"))
            .method(method, HttpRequest.BodyPublishers.noBody())
            .build()
        return codec.decode(HTTP.send(request, HttpResponse.BodyHandlers.ofString()).body()) as Map<String, Any?>
    }

    private fun stats() = control("GET", "")

    private fun newClient(): GraphLinkClient =
        GraphLinkClient(
            DefaultGraphLinkClientAdapter(GRAPHQL),
            DefaultGraphLinkGetAdapter(GRAPHQL),
            MockWebSocketAdapter(),
            DefaultGraphLinkClientAdapter(GRAPHQL),
            codec,
            codec,
        )

    @BeforeTest
    fun reset() {
        control("POST", "/reset")
        client = newClient()
    }

    @Test
    fun `a long query is registered on the first call - a GET miss, then a POST with the document`() = runTest {
        val res = client.queries.persistedLongQuery("user-1")

        assertEquals("Alice Smith", res.getUser.name)
        val stats = stats()
        assertEquals(1, intOf(stats, "misses"))
        assertEquals(1, intOf(stats, "registrations"))
        assertEquals(1, intOf(stats, "stored"))
        assertEquals(1, intOf(stats, "gets"))
    }

    @Test
    fun `a long query is a single GET hit once registered`() = runTest {
        client.queries.persistedLongQuery("user-1")

        val res = client.queries.persistedLongQuery("user-1")

        assertEquals("Alice Smith", res.getUser.name)
        val stats = stats()
        assertEquals(1, intOf(stats, "hits"))
        assertEquals(1, intOf(stats, "registrations"))
        assertEquals(2, intOf(stats, "gets"))
    }

    @Test
    fun `a fresh client reuses what the server already stored`() = runTest {
        client.queries.persistedLongQuery("user-1")

        val res = newClient().queries.persistedLongQuery("user-1")

        assertEquals("Alice Smith", res.getUser.name)
        val stats = stats()
        assertEquals(1, intOf(stats, "hits"))
        assertEquals(1, intOf(stats, "registrations"))
    }

    @Test
    fun `a long query is registered again after the server evicts it`() = runTest {
        client.queries.persistedLongQuery("user-1")
        control("POST", "/evict")

        val res = client.queries.persistedLongQuery("user-1")

        assertEquals("Alice Smith", res.getUser.name)
        val stats = stats()
        assertEquals(2, intOf(stats, "registrations"))
        assertEquals(1, intOf(stats, "stored"))
    }

    @Test
    fun `a long query still works when the server does not support persisted queries`() = runTest {
        control("POST", "/supported/false")

        val first = client.queries.persistedLongQuery("user-1")
        val second = client.queries.persistedLongQuery("user-1")

        assertEquals("Alice Smith", first.getUser.name)
        assertEquals("Alice Smith", second.getUser.name)
        val stats = stats()
        assertEquals(0, intOf(stats, "stored"))
        assertEquals(1, intOf(stats, "gets"))
    }

    @Test
    fun `a long mutation is registered and sent over POST, never GET`() = runTest {
        val res = client.mutations.persistedLongMutation(newUser)

        assertEquals("Persisted Pat", res.createUser.name)
        val stats = stats()
        assertEquals(1, intOf(stats, "registrations"))
        assertEquals(0, intOf(stats, "gets"))
    }

    @Test
    fun `a long mutation is a hash-only POST once registered`() = runTest {
        client.mutations.persistedLongMutation(newUser)

        val res = client.mutations.persistedLongMutation(newUser)

        assertEquals("pat@test.com", res.createUser.email)
        val stats = stats()
        assertEquals(1, intOf(stats, "hits"))
        assertEquals(1, intOf(stats, "registrations"))
        assertEquals(0, intOf(stats, "gets"))
    }

    @Test
    fun `a short query does not use persisted queries`() = runTest {
        val res = client.queries.persistedShortQuery()

        assertTrue(res.listUsers.isNotEmpty())
        val stats = stats()
        assertEquals(0, intOf(stats, "hits"))
        assertEquals(0, intOf(stats, "misses"))
        assertEquals(0, intOf(stats, "registrations"))
        assertEquals(0, intOf(stats, "gets"))
    }

    private fun intOf(stats: Map<String, Any?>, key: String): Int = (stats.getValue(key) as Number).toInt()

    private companion object {
        const val PORT = 9997
        const val GRAPHQL = "http://localhost:$PORT/graphql"
        val HTTP: HttpClient = HttpClient.newHttpClient()
    }
}
