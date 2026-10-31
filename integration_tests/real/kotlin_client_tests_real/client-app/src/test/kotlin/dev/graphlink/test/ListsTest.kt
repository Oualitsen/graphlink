package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.UserStatus
import dev.graphlink.test.generated.types.Tag
import dev.graphlink.test.generated.types.User
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.newRealClient

class ListsTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = newRealClient()
    }

    // ── Non-nullable list of objects ──────────────────────────────────────────

    @Nested
    inner class NonNullableListOfObjects {

        @Test
        fun listUsers_isNotNull() = runTest {
            assertNotNull(client.queries.listUsers().listUsers)
        }

        @Test
        fun listUsers_hasTwoItems() = runTest {
            assertEquals(2, client.queries.listUsers().listUsers.size)
        }

        @Test
        fun listUsers_firstItem_isUserType() = runTest {
            assertIs<User>(client.queries.listUsers().listUsers[0])
        }

        @Test
        fun listUsers_firstItem_hasCorrectId() = runTest {
            assertEquals("user-1", client.queries.listUsers().listUsers[0].id)
        }

        @Test
        fun listUsers_secondItem_hasCorrectId() = runTest {
            assertEquals("user-2", client.queries.listUsers().listUsers[1].id)
        }

        @Test
        fun listUsers_items_haveDeserializedEnums() = runTest {
            val users = client.queries.listUsers().listUsers
            assertEquals(UserStatus.ACTIVE, users[0].status)
            assertEquals(UserStatus.INACTIVE, users[1].status)
        }
    }

    // ── List with nullable item fields ────────────────────────────────────────

    @Nested
    inner class ListWithNullableItemFields {

        @Test
        fun getTags_hasTwoItems() = runTest {
            assertEquals(2, client.queries.getTags().getTags.size)
        }

        @Test
        fun getTags_firstItem_isTagType() = runTest {
            assertIs<Tag>(client.queries.getTags().getTags[0])
        }

        @Test
        fun getTags_firstItem_hasColor() = runTest {
            assertEquals("#0175C2", client.queries.getTags().getTags[0].color)
        }

        @Test
        fun getTags_secondItem_colorIsNull() = runTest {
            assertNull(client.queries.getTags().getTags[1].color)
        }

        @Test
        fun getTags_secondItem_hasLabel() = runTest {
            assertEquals("graphql", client.queries.getTags().getTags[1].label)
        }
    }

    // ── List of scalars on a type ─────────────────────────────────────────────

    @Nested
    inner class ListOfScalars {

        @Test
        fun tags_onAlice_isListOfStrings() = runTest {
            val tags: List<String> = client.queries.getUser("user-1").getUser.tags
            assertNotNull(tags)
            assertEquals(2, tags.size)
            assertEquals("admin", tags[0])
            assertEquals("beta", tags[1])
        }

        @Test
        fun tags_onBob_isEmpty() = runTest {
            val tags = client.queries.getUser("user-2").getUser.tags
            assertNotNull(tags)
            assertTrue(tags.isEmpty())
        }

        @Test
        fun scores_onAlice_isListOfInts() = runTest {
            val scores: List<Int>? = client.queries.getUser("user-1").getUser.scores
            assertNotNull(scores)
            assertEquals(listOf(10, 20, 30), scores)
        }

        @Test
        fun scores_onBob_isNull() = runTest {
            assertNull(client.queries.getUser("user-2").getUser.scores)
        }
    }

    // ── searchUsers ───────────────────────────────────────────────────────────

    @Nested
    inner class SearchUsers {

        @Test
        fun searchUsers_returnsMatchingUsers() = runTest {
            val res = client.queries.searchUsers("Alice", 10)
            assertNotNull(res.searchUsers)
            assertTrue(res.searchUsers.isNotEmpty())
            assertEquals("user-1", res.searchUsers[0].id)
        }

        @Test
        fun searchUsers_withLimit_respectsLimit() = runTest {
            val res = client.queries.searchUsers("", 1)
            assertNotNull(res.searchUsers)
            assertTrue(res.searchUsers.size <= 1)
        }
    }
}
