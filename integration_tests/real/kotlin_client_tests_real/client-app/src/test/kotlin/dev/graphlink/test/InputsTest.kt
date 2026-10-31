package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.Priority
import dev.graphlink.test.generated.enums.UserStatus
import dev.graphlink.test.generated.inputs.AddressInput
import dev.graphlink.test.generated.inputs.CreateUserInput
import dev.graphlink.test.generated.inputs.UpdateUserInput
import dev.graphlink.test.generated.types.CreateUserResponse
import dev.graphlink.test.generated.types.UpdateUserResponse
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.newRealClient

class InputsTest {

    private lateinit var client: GraphLinkClient

    private val kAddressInput = AddressInput("123 Main St", "Springfield", "US", "12345")

    @BeforeTest
    fun setUp() {
        client = newRealClient()
    }

    // ── CreateUserInput — required fields ─────────────────────────────────────

    @Nested
    inner class CreateUserInput_RequiredFields {

        private val minimalInput = CreateUserInput(
            name = "Alice Smith",
            email = "alice@test.com",
            status = UserStatus.ACTIVE,
            address = AddressInput("123 Main St", "Springfield", "US", "12345"),
        )

        @Test
        fun createUser_response_deserializesCorrectly() = runTest {
            val res: CreateUserResponse = client.mutations.createUser(minimalInput)
            assertNotNull(res.createUser)
            assertEquals("Alice Smith", res.createUser.name)
        }

        @Test
        fun createUser_address_isReflectedInResponse() = runTest {
            val res = client.mutations.createUser(minimalInput)
            assertNotNull(res.createUser.address)
            assertEquals("Springfield", res.createUser.address.city)
        }

        @Test
        fun createUser_status_isReflectedInResponse() = runTest {
            val res = client.mutations.createUser(minimalInput)
            assertEquals(UserStatus.ACTIVE, res.createUser.status)
        }
    }

    // ── CreateUserInput — optional fields ─────────────────────────────────────

    @Nested
    inner class CreateUserInput_OptionalFields {

        @Test
        fun createUser_withPriority_isReflectedInResponse() = runTest {
            val input = CreateUserInput(
                name = "Alice Smith", email = "alice@test.com",
                status = UserStatus.ACTIVE, address = kAddressInput,
                priority = Priority.HIGH,
            )
            val res: CreateUserResponse = client.mutations.createUser(input)
            assertEquals(Priority.HIGH, res.createUser.priority)
        }
    }

    // ── UpdateUserInput — all nullable fields ─────────────────────────────────

    @Nested
    inner class UpdateUserInput_AllNullable {

        @Test
        fun updateUser_response_deserializesCorrectly() = runTest {
            val input = UpdateUserInput(name = "Alice Updated")
            val res: UpdateUserResponse = client.mutations.updateUser("user-1", input)
            assertNotNull(res.updateUser)
            assertEquals("Alice Updated", res.updateUser.name)
        }

        @Test
        fun updateUser_statusNotInInput_preservesOriginalStatus() = runTest {
            val input = UpdateUserInput(name = "Alice Updated")
            val res = client.mutations.updateUser("user-1", input)
            assertEquals(UserStatus.ACTIVE, res.updateUser.status)
        }
    }

    // ── AddressInput — nullable zip (pure unit tests, no server needed) ────────

    @Nested
    inner class AddressInput_NullableZip {

        @Test
        fun addressInput_zip_isNull_whenNotSet() {
            val addr = AddressInput(street = "1 Road", city = "Town", country = "US")
            assertNull(addr.zip)
        }

        @Test
        fun addressInput_zip_isPresent_whenSet() {
            val addr = AddressInput(street = "1 Road", city = "Town", country = "US", zip = "00001")
            assertEquals("00001", addr.zip)
        }
    }
}
