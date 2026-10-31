package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec
import dev.graphlink.test.generated.enums.UserStatus
import dev.graphlink.test.generated.inputs.AddressInput
import dev.graphlink.test.generated.inputs.CreateUserInput
import dev.graphlink.test.generated.inputs.UpdateUserInput
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.kPostJson
import dev.graphlink.test.Fixtures.kUserAliceJson
import dev.graphlink.test.Fixtures.newClient

/**
 * Regression tests for Kotlin string interpolation in generated query strings.
 *
 * GraphQL variable syntax uses `$varName` which is also Kotlin's string
 * interpolation syntax. The generator must emit `\$varName` so the literal
 * dollar sign survives at runtime. These tests decode the raw outgoing payload
 * and assert the `query` field contains `$` as a real character — not the
 * toString() of a Kotlin object substituted by the compiler.
 */
class QueryStringsTest {

    private val codec = KotlinxSerializationGraphLinkJsonCodec()
    private lateinit var adapter: MockAdapter
    private lateinit var client: GraphLinkClient

    private val kAddressInput = AddressInput("123 Main St", "Springfield", "US", "12345")
    private val kCreateInput = CreateUserInput(
        name = "Alice Smith",
        email = "alice@test.com",
        status = UserStatus.ACTIVE,
        address = kAddressInput,
    )

    @BeforeTest
    fun setUp() {
        adapter = MockAdapter()
        client = newClient(adapter, MockWebSocketAdapter())
    }

    private fun lastQuery(): String {
        val raw = adapter.getLastCall()!!.rawPayload
        return codec.decode(raw)["query"] as String
    }

    // ── Mutations ─────────────────────────────────────────────────────────────

    @Nested
    inner class MutationQueryStrings {

        @Test
        fun createUser_query_containsLiteralDollarInput() = runTest {
            adapter.registerData("createUser", mapOf("createUser" to kUserAliceJson))
            client.mutations.createUser(kCreateInput)
            val query = lastQuery()
            assertTrue(query.contains("\$input"),
                "Expected '\$input' in query but got: $query")
        }

        @Test
        fun updateUser_query_containsLiteralDollarId_andDollarInput() = runTest {
            adapter.registerData("updateUser", mapOf("updateUser" to kUserAliceJson))
            client.mutations.updateUser("user-1", UpdateUserInput(name = "Alice"))
            val query = lastQuery()
            assertTrue(query.contains("\$id"),
                "Expected '\$id' in query but got: $query")
            assertTrue(query.contains("\$input"),
                "Expected '\$input' in query but got: $query")
        }

        @Test
        fun deleteUser_query_containsLiteralDollarId() = runTest {
            adapter.registerData("deleteUser", mapOf("deleteUser" to true))
            client.mutations.deleteUser("user-1")
            val query = lastQuery()
            assertTrue(query.contains("\$id"),
                "Expected '\$id' in query but got: $query")
        }

        @Test
        fun transferPost_query_containsLiteralDollarArgs() = runTest {
            adapter.registerData("transferPost", mapOf("transferPost" to kPostJson))
            client.mutations.transferPost("post-1", "user-2")
            val query = lastQuery()
            assertTrue(query.contains("\$postId"),
                "Expected '\$postId' in query but got: $query")
            assertTrue(query.contains("\$newAuthorId"),
                "Expected '\$newAuthorId' in query but got: $query")
        }

        @Test
        fun query_doesNotContainInputObjectToString() = runTest {
            adapter.registerData("createUser", mapOf("createUser" to kUserAliceJson))
            client.mutations.createUser(kCreateInput)
            val query = lastQuery()
            assertFalse(query.contains("CreateUserInput("),
                "Query must not contain Kotlin object toString; got: $query")
        }
    }

    // ── Simple queries ────────────────────────────────────────────────────────

    @Nested
    inner class QueryQueryStrings {

        @Test
        fun getUser_query_containsLiteralDollarId() = runTest {
            adapter.registerData("getUser", mapOf("getUser" to kUserAliceJson))
            client.queries.getUser("user-1")
            val query = lastQuery()
            assertTrue(query.contains("\$id"),
                "Expected '\$id' in query but got: $query")
        }

        @Test
        fun listUsersByStatus_query_containsLiteralDollarStatus() = runTest {
            adapter.registerData("listUsersByStatus", mapOf("listUsersByStatus" to listOf(kUserAliceJson)))
            client.queries.listUsersByStatus(UserStatus.ACTIVE)
            val query = lastQuery()
            assertTrue(query.contains("\$status"),
                "Expected '\$status' in query but got: $query")
        }
    }

    // ── Multi-resolver (partial query) path ───────────────────────────────────

    @Nested
    inner class PartialQueryStrings {

        @Test
        fun fetchUserAndPost_partialQueryStrings_containLiteralDollar() = runTest {
            adapter.registerData("fetchUserAndPost", mapOf(
                "user" to kUserAliceJson, "post" to kPostJson,
            ))
            client.queries.fetchUserAndPost("user-1", "post-1")
            val query = lastQuery()
            assertTrue(query.contains("\$userId"),
                "Expected '\$userId' in partial query but got: $query")
            assertTrue(query.contains("\$postId"),
                "Expected '\$postId' in partial query but got: $query")
        }

        @Test
        fun fetchUserAndPost_query_doesNotContainObjectToString() = runTest {
            adapter.registerData("fetchUserAndPost", mapOf(
                "user" to kUserAliceJson, "post" to kPostJson,
            ))
            client.queries.fetchUserAndPost("user-1", "post-1")
            val query = lastQuery()
            assertFalse(query.contains("user-1") && query.contains("post-1") && !query.contains("\$userId"),
                "Query must not contain interpolated arg values; got: $query")
        }
    }
}
