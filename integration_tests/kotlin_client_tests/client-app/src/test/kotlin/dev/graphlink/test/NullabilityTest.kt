package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.kPostJson
import dev.graphlink.test.Fixtures.kPostWithCoAuthorJson
import dev.graphlink.test.Fixtures.kUserAliceJson
import dev.graphlink.test.Fixtures.kUserBobJson
import dev.graphlink.test.Fixtures.newClient
import dev.graphlink.test.n

class NullabilityTest {

    private lateinit var adapter: MockAdapter
    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        adapter = MockAdapter()
        client = newClient(adapter, MockWebSocketAdapter())
    }

    // ── Non-nullable query return type ────────────────────────────────────────

    @Nested
    inner class NonNullableQueryReturn {

        @BeforeTest
        fun register() {
            adapter.registerData("getUser", mapOf("getUser" to kUserAliceJson))
        }

        @Test
        fun getUser_returnsNonNullUser() = runTest {
            assertNotNull(client.queries.getUser("user-1").getUser)
        }

        @Test
        fun getUser_hasCorrectId() = runTest {
            assertEquals("user-1", client.queries.getUser("user-1").getUser.id)
        }
    }

    // ── Nullable query return type — null ─────────────────────────────────────

    @Nested
    inner class NullableQueryReturn_Null {

        @BeforeTest
        fun register() {
            adapter.registerData("findUser", n("findUser" to null))
        }

        @Test
        fun findUser_returnsNull_whenServerReturnsNull() = runTest {
            assertNull(client.queries.findUser("user-99").findUser)
        }
    }

    // ── Nullable query return type — present ──────────────────────────────────

    @Nested
    inner class NullableQueryReturn_Present {

        @BeforeTest
        fun register() {
            adapter.registerData("findUser", mapOf("findUser" to kUserAliceJson))
        }

        @Test
        fun findUser_returnsUser_whenServerReturnsData() = runTest {
            val res = client.queries.findUser("user-1")
            assertNotNull(res.findUser)
            assertEquals("user-1", res.findUser!!.id)
        }
    }

    // ── Nullable nested object — null ─────────────────────────────────────────

    @Nested
    inner class NullableNestedObject_Null {

        @BeforeTest
        fun register() {
            adapter.registerData("getUser", mapOf("getUser" to kUserAliceJson))
        }

        @Test
        fun billingAddress_isNull_whenAbsent() = runTest {
            assertNull(client.queries.getUser("user-1").getUser.billingAddress)
        }
    }

    // ── Nullable nested object — present ──────────────────────────────────────

    @Nested
    inner class NullableNestedObject_Present {

        @BeforeTest
        fun register() {
            adapter.registerData("getUser", mapOf("getUser" to kUserBobJson))
        }

        @Test
        fun billingAddress_isNotNull_whenPresent() = runTest {
            assertNotNull(client.queries.getUser("user-2").getUser.billingAddress)
        }

        @Test
        fun billingAddress_hasCorrectCity() = runTest {
            assertEquals("Capital City", client.queries.getUser("user-2").getUser.billingAddress!!.city)
        }
    }

    // ── Nullable scalar on nested type ────────────────────────────────────────

    @Nested
    inner class NullableScalarOnNestedType {

        @Test
        fun address_zip_isNull_whenAbsent() = runTest {
            adapter.registerData("getUser", mapOf("getUser" to kUserBobJson))
            assertNull(client.queries.getUser("user-2").getUser.address.zip)
        }

        @Test
        fun address_zip_isPresent_whenSet() = runTest {
            adapter.registerData("getUser", mapOf("getUser" to kUserAliceJson))
            assertEquals("12345", client.queries.getUser("user-1").getUser.address.zip)
        }
    }

    // ── Nullable list field ───────────────────────────────────────────────────

    @Nested
    inner class NullableListField {

        @Test
        fun scores_isNull_whenAbsent() = runTest {
            adapter.registerData("getUser", mapOf("getUser" to kUserBobJson))
            assertNull(client.queries.getUser("user-2").getUser.scores)
        }

        @Test
        fun scores_hasList_whenPresent() = runTest {
            adapter.registerData("getUser", mapOf("getUser" to kUserAliceJson))
            val scores = client.queries.getUser("user-1").getUser.scores
            assertNotNull(scores)
            assertEquals(3, scores.size)
        }
    }

    // ── Nullable coAuthor on Post ─────────────────────────────────────────────

    @Nested
    inner class NullableCoAuthor {

        @Test
        fun coAuthor_isNull_whenAbsent() = runTest {
            adapter.registerData("getPost", mapOf("getPost" to kPostJson))
            assertNull(client.queries.getPost("post-1").getPost.coAuthor)
        }

        @Test
        fun coAuthor_isNotNull_whenPresent() = runTest {
            adapter.registerData("getPost", mapOf("getPost" to kPostWithCoAuthorJson))
            val coAuthor = client.queries.getPost("post-2").getPost.coAuthor
            assertNotNull(coAuthor)
            assertEquals("user-2", coAuthor.id)
        }
    }
}
