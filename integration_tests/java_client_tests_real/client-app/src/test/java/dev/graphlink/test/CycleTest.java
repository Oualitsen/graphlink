package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.types.Post;
import dev.graphlink.test.generated.types.User;
import dev.graphlink.test.generated.types.User_AddressBillingAddressEmail_aep45g;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class CycleTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    // ── User → posts list → post.author (truncated, no posts) ─────────────────

    @Nested
    class UserWithPosts {

        @Test
        void user_posts_isNotNull() {
            assertNotNull(client.queries.getUser("user-with-posts").getGetUser().getPosts());
        }

        @Test
        void user_posts_has4Entry() {
            assertEquals(4, client.queries.getUser("user-with-posts").getGetUser().getPosts().size());
        }

        @Test
        void user_posts_firstEntry_isPostType() {
            User user = client.queries.getUser("user-with-posts").getGetUser();
            assertInstanceOf(Post.class, user.getPosts().get(0));
        }

        @Test
        void user_posts_firstEntry_hasCorrectId() {
            User user = client.queries.getUser("user-with-posts").getGetUser();
            assertEquals("post-10", user.getPosts().get(0).getId());
        }

        @Test
        void user_posts_firstEntry_hasCorrectTitle() {
            User user = client.queries.getUser("user-with-posts").getGetUser();
            assertEquals("Cyclic Post", user.getPosts().get(0).getTitle());
        }

        @Test
        void user_posts_author_isTruncatedUserType() {
            User user = client.queries.getUser("user-with-posts").getGetUser();
            assertInstanceOf(User_AddressBillingAddressEmail_aep45g.class,
                    user.getPosts().get(0).getAuthor());
        }

        @Test
        void user_posts_author_hasCorrectId() {
            User user = client.queries.getUser("user-with-posts").getGetUser();
            assertEquals("user-1", user.getPosts().get(0).getAuthor().getId());
        }

        @Test
        void user_posts_author_address_isNotNull() {
            User user = client.queries.getUser("user-with-posts").getGetUser();
            assertNotNull(user.getPosts().get(0).getAuthor().getAddress());
        }

        @Test
        void user_posts_author_address_city_isAccessible() {
            User user = client.queries.getUser("user-with-posts").getGetUser();
            assertEquals("Springfield",
                    user.getPosts().get(0).getAuthor().getAddress().getCity());
        }
    }

    // ── User with posts: null ─────────────────────────────────────────────────

    @Nested
    class UserNullPosts {

        @Test
        void user_posts_isNull_forAlice() {
            User user = client.queries.getUser("user-1").getGetUser();
            assertNull(user.getPosts());
        }
    }

    // ── Post → author (truncated user, cycle broken) ──────────────────────────

    @Nested
    class PostCycleAuthor {

        @Test
        void post_author_isTruncatedUserType() {
            assertInstanceOf(User_AddressBillingAddressEmail_aep45g.class,
                    client.queries.getPost("post-10").getGetPost().getAuthor());
        }

        @Test
        void post_author_hasCorrectId() {
            assertEquals("user-1",
                    client.queries.getPost("post-10").getGetPost().getAuthor().getId());
        }

        @Test
        void post_author_address_isNotNull() {
            assertNotNull(
                    client.queries.getPost("post-10").getGetPost().getAuthor().getAddress());
        }

        @Test
        void post_coAuthor_isNull() {
            assertNull(client.queries.getPost("post-10").getGetPost().getCoAuthor());
        }
    }

    // ── Post with coAuthor ────────────────────────────────────────────────────

    @Nested
    class PostWithCoAuthor {

        @Test
        void post_coAuthor_isNotNull() {
            assertNotNull(client.queries.getPost("post-2").getGetPost().getCoAuthor());
        }

        @Test
        void post_coAuthor_isTruncatedUserType() {
            assertInstanceOf(User_AddressBillingAddressEmail_aep45g.class,
                    client.queries.getPost("post-2").getGetPost().getCoAuthor());
        }

        @Test
        void post_coAuthor_hasCorrectId() {
            assertEquals("user-2",
                    client.queries.getPost("post-2").getGetPost().getCoAuthor().getId());
        }

        @Test
        void post_author_and_coAuthor_haveDifferentIds() {
            Post post = client.queries.getPost("post-2").getGetPost();
            assertNotEquals(post.getAuthor().getId(), post.getCoAuthor().getId());
        }
    }
}
