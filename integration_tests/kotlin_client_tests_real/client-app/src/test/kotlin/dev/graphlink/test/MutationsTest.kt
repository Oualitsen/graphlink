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
import dev.graphlink.test.Fixtures.newRealClient

class MutationsTest {

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
        client = newRealClient()
    }

    // ── createUser ────────────────────────────────────────────────────────────

    @Nested
    inner class CreateUser {

        @Test
        fun response_returnsCreatedUser() = runTest {
            val res: CreateUserResponse = client.mutations.createUser(kCreateInput)
            assertNotNull(res.createUser)
        }

        @Test
        fun response_user_hasName() = runTest {
            val res = client.mutations.createUser(kCreateInput)
            assertEquals("Alice Smith", res.createUser.name)
        }

        @Test
        fun response_user_hasEmail() = runTest {
            val res = client.mutations.createUser(kCreateInput)
            assertEquals("alice@test.com", res.createUser.email)
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

        @Test
        fun response_returnsTrue() = runTest {
            val res: DeleteUserResponse = client.mutations.deleteUser("user-1")
            assertTrue(res.deleteUser)
        }
    }

    // ── updateUser ────────────────────────────────────────────────────────────

    @Nested
    inner class UpdateUser {

        @Test
        fun response_returnsUpdatedUser() = runTest {
            val input = UpdateUserInput(name = "Alice Updated")
            val res: UpdateUserResponse = client.mutations.updateUser("user-1", input)
            assertNotNull(res.updateUser)
            assertEquals("user-1", res.updateUser.id)
        }

        @Test
        fun response_user_hasUpdatedName() = runTest {
            val input = UpdateUserInput(name = "Alice Updated")
            val res = client.mutations.updateUser("user-1", input)
            assertEquals("Alice Updated", res.updateUser.name)
        }

        @Test
        fun response_user_statusUnchanged_whenNotInInput() = runTest {
            val input = UpdateUserInput(name = "Alice Updated")
            val res = client.mutations.updateUser("user-1", input)
            assertEquals(UserStatus.ACTIVE, res.updateUser.status)
        }
    }

    // ── transferPost ──────────────────────────────────────────────────────────

    @Nested
    inner class TransferPost {

        @Test
        fun response_returnsPost() = runTest {
            val res: TransferPostResponse = client.mutations.transferPost("post-1", "user-2")
            assertNotNull(res.transferPost)
            assertEquals("post-1", res.transferPost.id)
        }

        @Test
        fun response_post_authorIsNewOwner() = runTest {
            val res = client.mutations.transferPost("post-1", "user-2")
            assertEquals("user-2", res.transferPost.author?.id)
        }
    }

    // ── resetAll ──────────────────────────────────────────────────────────────

    @Nested
    inner class ResetAll {

        @Test
        fun response_returnsTrue() = runTest {
            val res: ResetAllResponse = client.mutations.resetAll()
            assertTrue(res.resetAll)
        }
    }
}
