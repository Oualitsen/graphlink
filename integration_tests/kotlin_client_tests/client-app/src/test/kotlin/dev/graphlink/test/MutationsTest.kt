package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.UserStatus
import dev.graphlink.test.generated.inputs.AddressInput
import dev.graphlink.test.generated.inputs.CreateUserInput
import dev.graphlink.test.generated.inputs.UpdateUserInput
import dev.graphlink.test.generated.types.CreateUserResponse
import dev.graphlink.test.generated.types.DeleteUserResponse
import dev.graphlink.test.generated.types.ResetAllResponse
import dev.graphlink.test.generated.types.TransferPostResponse
import dev.graphlink.test.generated.types.UpdateUserResponse
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.kUserAliceJson
import dev.graphlink.test.Fixtures.kPostJson
import dev.graphlink.test.Fixtures.newClient

class MutationsTest {

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

    // ── createUser ────────────────────────────────────────────────────────────

    @Nested
    inner class CreateUser {

        @BeforeTest
        fun register() {
            adapter.registerData("createUser", mapOf("createUser" to kUserAliceJson))
        }

        @Test
        fun operationName_isCreateUser() = runTest {
            client.mutations.createUser(kCreateInput)
            assertEquals("createUser", adapter.getLastCall()?.operationName)
        }

        @Test
        fun inputObject_isSentAsVariables() = runTest {
            client.mutations.createUser(kCreateInput)
            assertNotNull(adapter.getLastCall()?.variables?.get("input"))
        }

        @Test
        fun response_returnsCreatedUser() = runTest {
            val res: CreateUserResponse = client.mutations.createUser(kCreateInput)
            assertNotNull(res.createUser)
            assertEquals("user-1", res.createUser.id)
        }

        @Test
        fun response_user_hasCorrectStatus() = runTest {
            val res = client.mutations.createUser(kCreateInput)
            assertEquals(UserStatus.ACTIVE, res.createUser.status)
        }

        @Test
        fun response_user_hasNestedAddress() = runTest {
            val res = client.mutations.createUser(kCreateInput)
            assertNotNull(res.createUser.address)
            assertEquals("Springfield", res.createUser.address.city)
        }
    }

    // ── deleteUser ────────────────────────────────────────────────────────────

    @Nested
    inner class DeleteUser {

        @BeforeTest
        fun register() {
            adapter.registerData("deleteUser", mapOf("deleteUser" to true))
        }

        @Test
        fun operationName_isDeleteUser() = runTest {
            client.mutations.deleteUser("user-1")
            assertEquals("deleteUser", adapter.getLastCall()?.operationName)
        }

        @Test
        fun idArgument_isSentInVariables() = runTest {
            client.mutations.deleteUser("user-1")
            assertEquals("user-1", adapter.getLastCall()?.variables?.get("id"))
        }

        @Test
        fun response_returnsTrue() = runTest {
            val res: DeleteUserResponse = client.mutations.deleteUser("user-1")
            assertTrue(res.deleteUser)
        }
    }

    // ── updateUser ────────────────────────────────────────────────────────────

    @Nested
    inner class UpdateUser {

        @BeforeTest
        fun register() {
            adapter.registerData("updateUser", mapOf("updateUser" to kUserAliceJson))
        }

        @Test
        fun operationName_isUpdateUser() = runTest {
            client.mutations.updateUser("user-1", UpdateUserInput(name = "Alice Updated"))
            assertEquals("updateUser", adapter.getLastCall()?.operationName)
        }

        @Test
        fun idAndInput_areSentInVariables() = runTest {
            client.mutations.updateUser("user-1", UpdateUserInput(name = "Alice Updated"))
            assertEquals("user-1", adapter.getLastCall()?.variables?.get("id"))
            assertNotNull(adapter.getLastCall()?.variables?.get("input"))
        }

        @Test
        fun response_returnsUpdatedUser() = runTest {
            val res: UpdateUserResponse = client.mutations.updateUser("user-1", UpdateUserInput(status = UserStatus.INACTIVE))
            assertNotNull(res.updateUser)
            assertEquals("user-1", res.updateUser.id)
        }

        @Test
        fun nullableField_inInput_isSentAsNull() = runTest {
            client.mutations.updateUser("user-1", UpdateUserInput())
            @Suppress("UNCHECKED_CAST")
            val inputVar = adapter.getLastCall()?.variables?.get("input") as? Map<String, Any?>
            assertNotNull(inputVar)
            assertNull(inputVar["status"])
        }
    }

    // ── transferPost ──────────────────────────────────────────────────────────

    @Nested
    inner class TransferPost {

        @BeforeTest
        fun register() {
            adapter.registerData("transferPost", mapOf("transferPost" to kPostJson))
        }

        @Test
        fun operationName_isTransferPost() = runTest {
            client.mutations.transferPost("post-1", "user-2")
            assertEquals("transferPost", adapter.getLastCall()?.operationName)
        }

        @Test
        fun bothArgs_areSentInVariables() = runTest {
            client.mutations.transferPost("post-1", "user-2")
            assertEquals("post-1", adapter.getLastCall()?.variables?.get("postId"))
            assertEquals("user-2", adapter.getLastCall()?.variables?.get("newAuthorId"))
        }

        @Test
        fun response_returnsPost() = runTest {
            val res: TransferPostResponse = client.mutations.transferPost("post-1", "user-2")
            assertNotNull(res.transferPost)
            assertEquals("post-1", res.transferPost.id)
        }
    }

    // ── resetAll ──────────────────────────────────────────────────────────────

    @Nested
    inner class ResetAll {

        @BeforeTest
        fun register() {
            adapter.registerData("resetAll", mapOf("resetAll" to true))
        }

        @Test
        fun operationName_isResetAll() = runTest {
            client.mutations.resetAll()
            assertEquals("resetAll", adapter.getLastCall()?.operationName)
        }

        @Test
        fun response_returnsTrue() = runTest {
            val res: ResetAllResponse = client.mutations.resetAll()
            assertTrue(res.resetAll)
        }
    }

    // ── Call count sanity ─────────────────────────────────────────────────────

    @Nested
    inner class CallCount {

        @Test
        fun eachMutationCallIsRecorded() = runTest {
            adapter.registerData("createUser", mapOf("createUser" to kUserAliceJson))
            adapter.registerData("deleteUser", mapOf("deleteUser" to true))
            client.mutations.createUser(kCreateInput)
            client.mutations.deleteUser("user-1")
            assertEquals(2, adapter.getCallCount())
        }
    }
}
