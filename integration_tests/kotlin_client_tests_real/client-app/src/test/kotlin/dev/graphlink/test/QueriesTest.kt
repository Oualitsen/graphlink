package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.UserStatus
import dev.graphlink.test.generated.interfaces.SearchResult
import dev.graphlink.test.generated.types.PostResult
import dev.graphlink.test.generated.types.User_IdNameStatus
import dev.graphlink.test.generated.types.UserResult
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.newRealClient

class QueriesTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = newRealClient()
    }

    // ── fetchUserAndPost — multi-resolver, single round-trip ──────────────────

    @Nested
    inner class FetchUserAndPost {

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
    }

    // ── fetchUserSummary — partial projection ─────────────────────────────────

    @Nested
    inner class FetchUserSummary {

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

    // ── runSearch — interface dispatch via __typename ─────────────────────────

    @Nested
    inner class RunSearch {

        @Test
        fun results_containUserResult() = runTest {
            val results: List<SearchResult> = client.queries.runSearch("alice").search
            assertNotNull(results)
            assertTrue(results.any { it is UserResult })
        }

        @Test
        fun results_containPostResult() = runTest {
            val results = client.queries.runSearch("alice").search
            assertNotNull(results)
            assertTrue(results.any { it is PostResult })
        }

        @Test
        fun userResult_hasCorrectId() = runTest {
            val results = client.queries.runSearch("alice").search
            val user = results.filterIsInstance<UserResult>().first()
            assertEquals("user-1", user.id)
            assertEquals("Alice Smith", user.name)
        }

        @Test
        fun postResult_hasCorrectId() = runTest {
            val results = client.queries.runSearch("alice").search
            val post = results.filterIsInstance<PostResult>().first()
            assertEquals("post-1", post.id)
        }
    }
}
