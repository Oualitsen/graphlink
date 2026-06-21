package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.types.Post
import dev.graphlink.test.generated.types.User
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.kPostWithAuthorCycleJson
import dev.graphlink.test.Fixtures.kPostWithCoAuthorJson
import dev.graphlink.test.Fixtures.kUserAliceJson
import dev.graphlink.test.Fixtures.kUserWithPostsJson
import dev.graphlink.test.Fixtures.newClient

class CycleTest {

    private lateinit var adapter: MockAdapter
    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        adapter = MockAdapter()
        client = newClient(adapter, MockWebSocketAdapter())
    }

    // ── User → posts → post.author (cycle broken) ─────────────────────────────

    @Nested
    inner class UserWithPosts {

        @BeforeTest
        fun register() {
            adapter.registerData("getUser", mapOf("getUser" to kUserWithPostsJson))
        }

        @Test
        fun user_posts_isNotNull() = runTest {
            assertNotNull(client.queries.getUser("user-1").getUser.posts)
        }

        @Test
        fun user_posts_hasOneEntry() = runTest {
            assertEquals(1, client.queries.getUser("user-1").getUser.posts!!.size)
        }

        @Test
        fun user_posts_firstEntry_isPostType() = runTest {
            assertIs<Post>(client.queries.getUser("user-1").getUser.posts!![0])
        }

        @Test
        fun user_posts_firstEntry_hasCorrectId() = runTest {
            assertEquals("post-10", client.queries.getUser("user-1").getUser.posts!![0].id)
        }

        @Test
        fun user_posts_firstEntry_hasCorrectTitle() = runTest {
            assertEquals("Cyclic Post", client.queries.getUser("user-1").getUser.posts!![0].title)
        }

        @Test
        fun user_posts_author_isTruncatedUserType() = runTest {
            assertIs<User>(
                client.queries.getUser("user-1").getUser.posts!![0].author
            )
        }

        @Test
        fun user_posts_author_hasCorrectId() = runTest {
            assertEquals("user-1", client.queries.getUser("user-1").getUser.posts!![0].author?.id)
        }

        @Test
        fun user_posts_author_address_isNotNull() = runTest {
            assertNotNull(client.queries.getUser("user-1").getUser.posts!![0].author?.address)
        }

        @Test
        fun user_posts_author_address_city_isAccessible() = runTest {
            assertEquals(
                "Springfield",
                client.queries.getUser("user-1").getUser.posts!![0].author?.address?.city,
            )
        }
    }

    // ── User with posts: null ─────────────────────────────────────────────────

    @Nested
    inner class UserNullPosts {

        @Test
        fun user_posts_isNull_whenNotPopulated() = runTest {
            adapter.registerData("getUser", mapOf("getUser" to kUserAliceJson))
            val user: User = client.queries.getUser("user-1").getUser
            assertNull(user.posts)
        }
    }

    // ── Post → author (truncated user) ────────────────────────────────────────

    @Nested
    inner class PostCycleAuthor {

        @BeforeTest
        fun register() {
            adapter.registerData("getPost", mapOf("getPost" to kPostWithAuthorCycleJson))
        }

        @Test
        fun post_author_isTruncatedUserType() = runTest {
            assertIs<User>(
                client.queries.getPost("post-10").getPost.author
            )
        }

        @Test
        fun post_author_hasCorrectId() = runTest {
            assertEquals("user-1", client.queries.getPost("post-10").getPost.author?.id)
        }

        @Test
        fun post_author_address_isNotNull() = runTest {
            assertNotNull(client.queries.getPost("post-10").getPost.author?.address)
        }

        @Test
        fun post_coAuthor_isNull() = runTest {
            assertNull(client.queries.getPost("post-10").getPost.coAuthor)
        }
    }

    // ── Post with coAuthor ────────────────────────────────────────────────────

    @Nested
    inner class PostWithCoAuthor {

        @BeforeTest
        fun register() {
            adapter.registerData("getPost", mapOf("getPost" to kPostWithCoAuthorJson))
        }

        @Test
        fun post_coAuthor_isNotNull() = runTest {
            assertNotNull(client.queries.getPost("post-2").getPost.coAuthor)
        }

        @Test
        fun post_coAuthor_isTruncatedUserType() = runTest {
            assertIs<User>(
                client.queries.getPost("post-2").getPost.coAuthor
            )
        }

        @Test
        fun post_coAuthor_hasCorrectId() = runTest {
            assertEquals("user-2", client.queries.getPost("post-2").getPost.coAuthor!!.id)
        }

        @Test
        fun post_author_and_coAuthor_haveDifferentIds() = runTest {
            val post: Post = client.queries.getPost("post-2").getPost
            assertNotEquals(post.author?.id, post.coAuthor!!.id)
        }
    }
}
