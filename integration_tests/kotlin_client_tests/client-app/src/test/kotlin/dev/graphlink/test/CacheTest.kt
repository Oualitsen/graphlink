package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.UserStatus
import dev.graphlink.test.generated.inputs.AddressInput
import dev.graphlink.test.generated.inputs.CreateUserInput
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.kPostJson
import dev.graphlink.test.Fixtures.kUserAliceJson
import dev.graphlink.test.Fixtures.kUserBobJson
import dev.graphlink.test.Fixtures.newClient
import dev.graphlink.test.n

class CacheTest {

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

    // ── Cache hit ─────────────────────────────────────────────────────────────

    @Nested
    inner class CacheHit {

        @BeforeTest
        fun register() {
            adapter.registerData("getCachedUser", mapOf("getCachedUser" to kUserAliceJson))
        }

        @Test
        fun firstCall_hitsAdapter() = runTest {
            client.queries.getCachedUser("user-1")
            assertEquals(1, adapter.getCallCount())
        }

        @Test
        fun secondCallSameArg_servedFromCache_noExtraAdapterCall() = runTest {
            client.queries.getCachedUser("user-1")
            client.queries.getCachedUser("user-1")
            assertEquals(1, adapter.getCallCount())
        }

        @Test
        fun cachedResponse_hasCorrectData() = runTest {
            client.queries.getCachedUser("user-1")
            val res = client.queries.getCachedUser("user-1")
            assertNotNull(res.getCachedUser)
            assertEquals("user-1", res.getCachedUser.id)
        }

        @Test
        fun differentArg_bypassesCache() = runTest {
            adapter.registerData("getCachedUser", mapOf("getCachedUser" to kUserBobJson))
            client.queries.getCachedUser("user-1")
            client.queries.getCachedUser("user-2")
            assertEquals(2, adapter.getCallCount())
        }
    }

    // ── Tag-based invalidation ────────────────────────────────────────────────

    @Nested
    inner class TagInvalidation {

        @Test
        fun createCachedUser_invalidatesUsersTag_nextGetCachedUserRefetches() = runTest {
            adapter.registerData("getCachedUser", mapOf("getCachedUser" to kUserAliceJson))
            adapter.registerData("createCachedUser", mapOf("createCachedUser" to kUserAliceJson))

            client.queries.getCachedUser("user-1")
            assertEquals(1, adapter.getCallCount())

            client.mutations.createCachedUser(kCreateInput)
            assertEquals(2, adapter.getCallCount())

            client.queries.getCachedUser("user-1")
            assertEquals(3, adapter.getCallCount())
        }

        @Test
        fun resetAll_invalidatesAllTags_allCachedQueriesRefetch() = runTest {
            adapter.registerData("getCachedUser", mapOf("getCachedUser" to kUserAliceJson))
            adapter.registerData("getCachedPost", mapOf("getCachedPost" to kPostJson))
            adapter.registerData("resetAll", mapOf("resetAll" to true))

            client.queries.getCachedUser("user-1")
            client.queries.getCachedPost("post-1")
            assertEquals(2, adapter.getCallCount())

            client.mutations.resetAll()
            assertEquals(3, adapter.getCallCount())

            client.queries.getCachedUser("user-1")
            client.queries.getCachedPost("post-1")
            assertEquals(5, adapter.getCallCount())
        }
    }

    // ── Cross-tag isolation ───────────────────────────────────────────────────

    @Nested
    inner class CrossTagIsolation {

        @Test
        fun usersTagInvalidation_doesNotAffect_postsCache() = runTest {
            adapter.registerData("getCachedPost", mapOf("getCachedPost" to kPostJson))
            adapter.registerData("createCachedUser", mapOf("createCachedUser" to kUserAliceJson))

            client.queries.getCachedPost("post-1")
            assertEquals(1, adapter.getCallCount())

            client.mutations.createCachedUser(kCreateInput)
            assertEquals(2, adapter.getCallCount())

            client.queries.getCachedPost("post-1")
            assertEquals(2, adapter.getCallCount())
        }

        @Test
        fun transferPost_invalidatesBothTags() = runTest {
            adapter.registerData("getCachedUser", mapOf("getCachedUser" to kUserAliceJson))
            adapter.registerData("getCachedPost", mapOf("getCachedPost" to kPostJson))
            adapter.registerData("transferPost", mapOf("transferPost" to kPostJson))

            client.queries.getCachedUser("user-1")
            client.queries.getCachedPost("post-1")
            assertEquals(2, adapter.getCallCount())

            client.mutations.transferPost("post-1", "user-2")
            assertEquals(3, adapter.getCallCount())

            client.queries.getCachedUser("user-1")
            client.queries.getCachedPost("post-1")
            assertEquals(5, adapter.getCallCount())
        }
    }

    // ── listCachedUsers ───────────────────────────────────────────────────────

    @Nested
    inner class ListCachedUsers {

        @Test
        fun listCachedUsers_isCachedAfterFirstCall() = runTest {
            adapter.registerData("listCachedUsers", mapOf("listCachedUsers" to listOf(kUserAliceJson)))
            client.queries.listCachedUsers()
            client.queries.listCachedUsers()
            assertEquals(1, adapter.getCallCount())
        }

        @Test
        fun createCachedUser_invalidatesListCachedUsers() = runTest {
            adapter.registerData("listCachedUsers", mapOf("listCachedUsers" to listOf(kUserAliceJson)))
            adapter.registerData("createCachedUser", mapOf("createCachedUser" to kUserAliceJson))

            client.queries.listCachedUsers()
            client.mutations.createCachedUser(kCreateInput)
            client.queries.listCachedUsers()
            assertEquals(3, adapter.getCallCount())
        }
    }

    // ── staleIfOffline ────────────────────────────────────────────────────────

    @Nested
    inner class StaleIfOffline {

        @Test
        fun staleData_isReturnedWhenNetworkFails_afterTtlExpires() = runTest {
            adapter.registerData("getStaleUser", n("getStaleUser" to kUserAliceJson))

            client.queries.getStaleUser("user-1")
            assertEquals(1, adapter.getCallCount())

            @Suppress("BlockingMethodInNonBlockingContext")
            Thread.sleep(1100) // wait for TTL to expire (TTL = 1s, uses real time)

            adapter.simulateFailure = true
            val res = client.queries.getStaleUser("user-1")

            assertNotNull(res.getStaleUser)
            assertEquals("user-1", res.getStaleUser.id)
        }

        @Test
        fun nonStaleEntry_throwsWhenNetworkFails() = runTest {
            adapter.registerData("getCachedUser", mapOf("getCachedUser" to kUserAliceJson))
            adapter.simulateFailure = true
            assertFailsWith<Exception> {
                client.queries.getCachedUser("user-1")
            }
        }
    }
}
