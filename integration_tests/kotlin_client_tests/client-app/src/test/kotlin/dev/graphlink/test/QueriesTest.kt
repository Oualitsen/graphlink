package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.UserStatus
import dev.graphlink.test.generated.interfaces.SearchResult
import dev.graphlink.test.generated.types.FetchCachedPairResponse
import dev.graphlink.test.generated.types.PostResult
import dev.graphlink.test.generated.types.User_IdNameStatus
import dev.graphlink.test.generated.types.UserResult
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.kPostJson
import dev.graphlink.test.Fixtures.kUserAliceJson
import dev.graphlink.test.Fixtures.kUserBobJson
import dev.graphlink.test.Fixtures.newClient
import dev.graphlink.test.n

class QueriesTest {

    private lateinit var adapter: MockAdapter
    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        adapter = MockAdapter()
        client = newClient(adapter, MockWebSocketAdapter())
    }

    // ── fetchUserAndPost ──────────────────────────────────────────────────────

    @Nested
    inner class FetchUserAndPost {

        @BeforeTest
        fun register() {
            adapter.registerData("fetchUserAndPost", n(
                "user" to kUserAliceJson,
                "post" to kPostJson,
            ))
        }

        @Test
        fun response_isNotNull() = runTest {
            assertNotNull(client.queries.fetchUserAndPost("user-1", "post-1"))
        }

        @Test
        fun user_isNotNull() = runTest {
            assertNotNull(client.queries.fetchUserAndPost("user-1", "post-1").user)
        }

        @Test
        fun user_hasCorrectId() = runTest {
            assertEquals("user-1", client.queries.fetchUserAndPost("user-1", "post-1").user.id)
        }

        @Test
        fun user_hasCorrectName() = runTest {
            assertEquals("Alice Smith", client.queries.fetchUserAndPost("user-1", "post-1").user.name)
        }

        @Test
        fun post_isNotNull() = runTest {
            assertNotNull(client.queries.fetchUserAndPost("user-1", "post-1").post)
        }

        @Test
        fun post_hasCorrectId() = runTest {
            assertEquals("post-1", client.queries.fetchUserAndPost("user-1", "post-1").post.id)
        }

        @Test
        fun post_hasCorrectTitle() = runTest {
            assertEquals("Hello World", client.queries.fetchUserAndPost("user-1", "post-1").post.title)
        }

        @Test
        fun post_author_hasCorrectId() = runTest {
            assertEquals("user-1", client.queries.fetchUserAndPost("user-1", "post-1").post.author.id)
        }

        @Test
        fun singleAdapterCall_forBothResolvers() = runTest {
            client.queries.fetchUserAndPost("user-1", "post-1")
            assertEquals(1, adapter.getCallCount())
        }
    }

    // ── fetchUserSummary ──────────────────────────────────────────────────────

    @Nested
    inner class FetchUserSummary {

        @BeforeTest
        fun register() {
            adapter.registerData("fetchUserSummary", mapOf(
                "getUser" to mapOf("id" to "user-1", "name" to "Alice Smith", "status" to "ACTIVE"),
            ))
        }

        @Test
        fun response_isNotNull() = runTest {
            assertNotNull(client.queries.fetchUserSummary("user-1"))
        }

        @Test
        fun getUser_isNotNull() = runTest {
            assertNotNull(client.queries.fetchUserSummary("user-1").getUser)
        }

        @Test
        fun getUser_isProjectedType() = runTest {
            assertIs<User_IdNameStatus>(client.queries.fetchUserSummary("user-1").getUser)
        }

        @Test
        fun getUser_hasCorrectId() = runTest {
            assertEquals("user-1", client.queries.fetchUserSummary("user-1").getUser.id)
        }

        @Test
        fun getUser_hasCorrectName() = runTest {
            assertEquals("Alice Smith", client.queries.fetchUserSummary("user-1").getUser.name)
        }

        @Test
        fun getUser_status_deserializesToEnum() = runTest {
            assertEquals(UserStatus.ACTIVE, client.queries.fetchUserSummary("user-1").getUser.status)
        }
    }

    // ── runSearch ─────────────────────────────────────────────────────────────

    @Nested
    inner class RunSearch {

        @Test
        fun userResult_dispatchedCorrectly() = runTest {
            adapter.registerData("runSearch", mapOf(
                "search" to listOf(n(
                    "__typename" to "UserResult",
                    "id"         to "u-1",
                    "name"       to "Alice",
                    "email"      to "alice@test.com",
                )),
            ))
            val results: List<SearchResult> = client.queries.runSearch("alice").search
            assertEquals(1, results.size)
            assertIs<UserResult>(results[0])
            assertEquals("u-1", results[0].id)
            assertEquals("Alice", (results[0] as UserResult).name)
        }

        @Test
        fun postResult_dispatchedCorrectly() = runTest {
            adapter.registerData("runSearch", mapOf(
                "search" to listOf(n("__typename" to "PostResult", "id" to "p-1", "title" to "Hello")),
            ))
            val results = client.queries.runSearch("hello").search
            assertEquals(1, results.size)
            assertIs<PostResult>(results[0])
            assertEquals("p-1", results[0].id)
            assertEquals("Hello", (results[0] as PostResult).title)
        }

        @Test
        fun mixedResults_dispatchedByTypename() = runTest {
            adapter.registerData("runSearch", mapOf(
                "search" to listOf(
                    n("__typename" to "UserResult", "id" to "u-1", "name" to "Alice", "email" to "alice@test.com"),
                    n("__typename" to "PostResult", "id" to "p-1", "title" to "Hello"),
                ),
            ))
            val results = client.queries.runSearch("a").search
            assertEquals(2, results.size)
            assertIs<UserResult>(results[0])
            assertIs<PostResult>(results[1])
        }

        @Test
        fun emptyResults_returnEmptyList() = runTest {
            adapter.registerData("runSearch", mapOf("search" to emptyList<Any>()))
            val results = client.queries.runSearch("xyz").search
            assertNotNull(results)
            assertTrue(results.isEmpty())
        }
    }

    // ── fetchCachedPair ───────────────────────────────────────────────────────

    @Nested
    inner class FetchCachedPair {

        @BeforeTest
        fun register() {
            adapter.registerData("fetchCachedPair", n(
                "user" to kUserAliceJson,
                "post" to kPostJson,
            ))
        }

        @Test
        fun firstCall_hitsAdapter() = runTest {
            client.queries.fetchCachedPair("user-1", "post-1")
            assertEquals(1, adapter.getCallCount())
        }

        @Test
        fun secondCall_servedFromCache() = runTest {
            client.queries.fetchCachedPair("user-1", "post-1")
            client.queries.fetchCachedPair("user-1", "post-1")
            assertEquals(1, adapter.getCallCount())
        }

        @Test
        fun cachedResponse_user_hasCorrectId() = runTest {
            client.queries.fetchCachedPair("user-1", "post-1")
            val res: FetchCachedPairResponse = client.queries.fetchCachedPair("user-1", "post-1")
            assertEquals("user-1", res.user.id)
        }

        @Test
        fun cachedResponse_post_hasCorrectId() = runTest {
            client.queries.fetchCachedPair("user-1", "post-1")
            val res = client.queries.fetchCachedPair("user-1", "post-1")
            assertEquals("post-1", res.post.id)
        }

        @Test
        fun differentArgs_bypassCache() = runTest {
            adapter.registerData("fetchCachedPair", n("user" to kUserBobJson, "post" to kPostJson))
            client.queries.fetchCachedPair("user-1", "post-1")
            client.queries.fetchCachedPair("user-2", "post-1")
            assertEquals(2, adapter.getCallCount())
        }
    }
}
