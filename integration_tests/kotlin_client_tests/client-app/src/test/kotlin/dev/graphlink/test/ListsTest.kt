package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.UserStatus
import dev.graphlink.test.generated.types.Tag
import dev.graphlink.test.generated.types.User
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.kTagsJson
import dev.graphlink.test.Fixtures.kUserAliceJson
import dev.graphlink.test.Fixtures.kUserBobJson
import dev.graphlink.test.Fixtures.newClient

class ListsTest {

    private lateinit var adapter: MockAdapter
    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        adapter = MockAdapter()
        client = newClient(adapter, MockWebSocketAdapter())
    }

    // ── Non-nullable list of objects ──────────────────────────────────────────

    @Nested
    inner class NonNullableListOfObjects {

        @BeforeTest
        fun register() {
            adapter.registerData("listUsers", mapOf("listUsers" to listOf(kUserAliceJson, kUserBobJson)))
        }

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

    // ── Empty list ────────────────────────────────────────────────────────────

    @Nested
    inner class EmptyList {

        @Test
        fun listUsers_empty_returnsEmptyList() = runTest {
            adapter.registerData("listUsers", mapOf("listUsers" to emptyList<Any>()))
            val res = client.queries.listUsers()
            assertNotNull(res.listUsers)
            assertTrue(res.listUsers.isEmpty())
        }
    }

    // ── List with nullable item fields ────────────────────────────────────────

    @Nested
    inner class ListWithNullableItemFields {

        @BeforeTest
        fun register() {
            adapter.registerData("getTags", mapOf("getTags" to kTagsJson))
        }

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
        fun tags_onUser_isListOfStrings() = runTest {
            adapter.registerData("getUser", mapOf("getUser" to kUserAliceJson))
            val tags: List<String> = client.queries.getUser("user-1").getUser.tags
            assertNotNull(tags)
            assertEquals(2, tags.size)
            assertEquals("admin", tags[0])
            assertEquals("beta", tags[1])
        }

        @Test
        fun tags_empty_returnsEmptyList() = runTest {
            adapter.registerData("getUser", mapOf("getUser" to kUserBobJson))
            val tags = client.queries.getUser("user-2").getUser.tags
            assertNotNull(tags)
            assertTrue(tags.isEmpty())
        }

        @Test
        fun scores_onUser_isListOfInts() = runTest {
            adapter.registerData("getUser", mapOf("getUser" to kUserAliceJson))
            val scores: List<Int>? = client.queries.getUser("user-1").getUser.scores
            assertNotNull(scores)
            assertEquals(listOf(10, 20, 30), scores)
        }
    }

    // ── searchUsers ───────────────────────────────────────────────────────────

    @Nested
    inner class SearchUsers {

        @BeforeTest
        fun register() {
            adapter.registerData("searchUsers", mapOf("searchUsers" to listOf(kUserAliceJson)))
        }

        @Test
        fun searchUsers_sendsNameAndLimit() = runTest {
            client.queries.searchUsers("Alice", 10)
            val vars = adapter.getLastCall()!!.variables
            assertEquals("Alice", vars["name"])
            assertEquals(10, (vars["limit"] as Number).toInt())
        }

        @Test
        fun searchUsers_returnsMatchingUsers() = runTest {
            val res = client.queries.searchUsers("Alice", 10)
            assertNotNull(res.searchUsers)
            assertEquals(1, res.searchUsers.size)
            assertEquals("user-1", res.searchUsers[0].id)
        }
    }
}
