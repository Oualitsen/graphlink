package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.UserStatus
import dev.graphlink.test.generated.types.Address
import dev.graphlink.test.generated.types.AuditEntry
import dev.graphlink.test.generated.types.Post
import dev.graphlink.test.generated.types.User
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.kAuditEntryJson
import dev.graphlink.test.Fixtures.kAuditEntryWithExtraJson
import dev.graphlink.test.Fixtures.kPostJson
import dev.graphlink.test.Fixtures.kUserAliceJson
import dev.graphlink.test.Fixtures.newClient

class NestedTypesTest {

    private lateinit var adapter: MockAdapter
    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        adapter = MockAdapter()
        client = newClient(adapter, MockWebSocketAdapter())
    }

    // ── Required nested object (User.address) ─────────────────────────────────

    @Nested
    inner class RequiredNestedObject {

        @BeforeTest
        fun register() {
            adapter.registerData("getUser", mapOf("getUser" to kUserAliceJson))
        }

        @Test
        fun address_isNotNull() = runTest {
            assertNotNull(client.queries.getUser("user-1").getUser.address)
        }

        @Test
        fun address_hasCorrectStreet() = runTest {
            assertEquals("123 Main St", client.queries.getUser("user-1").getUser.address.street)
        }

        @Test
        fun address_hasCorrectCity() = runTest {
            assertEquals("Springfield", client.queries.getUser("user-1").getUser.address.city)
        }

        @Test
        fun address_hasCorrectCountry() = runTest {
            assertEquals("US", client.queries.getUser("user-1").getUser.address.country)
        }

        @Test
        fun address_hasCorrectZip() = runTest {
            assertEquals("12345", client.queries.getUser("user-1").getUser.address.zip)
        }

        @Test
        fun address_deserializesToAddressType() = runTest {
            assertIs<Address>(client.queries.getUser("user-1").getUser.address)
        }
    }

    // ── Multi-level nesting (Post → User) ─────────────────────────────────────

    @Nested
    inner class MultiLevelNesting {

        @BeforeTest
        fun register() {
            adapter.registerData("getPost", mapOf("getPost" to kPostJson))
        }

        @Test
        fun post_isNotNull() = runTest {
            assertNotNull(client.queries.getPost("post-1").getPost)
        }

        @Test
        fun post_deserializesToPostType() = runTest {
            assertIs<Post>(client.queries.getPost("post-1").getPost)
        }

        @Test
        fun post_hasCorrectTitle() = runTest {
            assertEquals("Hello World", client.queries.getPost("post-1").getPost.title)
        }

        @Test
        fun post_author_isNotNull() = runTest {
            assertNotNull(client.queries.getPost("post-1").getPost.author)
        }

        @Test
        fun post_author_deserializesToFragmentType() = runTest {
            assertIs<User>(client.queries.getPost("post-1").getPost.author)
        }

        @Test
        fun post_author_hasCorrectId() = runTest {
            assertEquals("user-1", client.queries.getPost("post-1").getPost.author?.id)
        }

        @Test
        fun post_author_status_deserializesToEnum() = runTest {
            assertEquals(UserStatus.ACTIVE, client.queries.getPost("post-1").getPost.author?.status)
        }

        @Test
        fun post_author_address_city_isAccessible() = runTest {
            assertEquals("Springfield", client.queries.getPost("post-1").getPost.author?.address?.city)
        }

        @Test
        fun post_viewCount_deserializesToInt() = runTest {
            assertEquals(128, client.queries.getPost("post-1").getPost.viewCount)
        }
    }

    // ── @glSkipOnClient — server-only field silently ignored ──────────────────

    @Nested
    inner class SkipOnClientField {

        @Test
        fun auditEntry_withoutInternalNote_deserializesCorrectly() = runTest {
            adapter.registerData("getAuditEntry", mapOf("getAuditEntry" to kAuditEntryJson))
            val entry: AuditEntry = client.queries.getAuditEntry("audit-1").getAuditEntry
            assertNotNull(entry)
            assertEquals("audit-1", entry.id)
            assertEquals("LOGIN", entry.action)
            assertEquals("user-1", entry.performedBy)
        }

        @Test
        fun auditEntry_withExtraServerField_isIgnoredSilently() = runTest {
            adapter.registerData("getAuditEntry", mapOf("getAuditEntry" to kAuditEntryWithExtraJson))
            val entry: AuditEntry = client.queries.getAuditEntry("audit-2").getAuditEntry
            assertNotNull(entry)
            assertEquals("audit-2", entry.id)
            assertEquals("LOGOUT", entry.action)
        }
    }
}
