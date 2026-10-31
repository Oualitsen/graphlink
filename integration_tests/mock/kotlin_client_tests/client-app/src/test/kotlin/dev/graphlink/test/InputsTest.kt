package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.Priority
import dev.graphlink.test.generated.enums.UserStatus
import dev.graphlink.test.generated.inputs.AddressInput
import dev.graphlink.test.generated.inputs.CreateUserInput
import dev.graphlink.test.generated.inputs.UpdateUserInput
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.kUserAliceJson
import dev.graphlink.test.Fixtures.newClient

class InputsTest {

    private lateinit var adapter: MockAdapter
    private lateinit var client: GraphLinkClient

    private val kAddressInput = AddressInput("123 Main St", "Springfield", "US", "12345")

    @BeforeTest
    fun setUp() {
        adapter = MockAdapter()
        client = newClient(adapter, MockWebSocketAdapter())
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

        @BeforeTest
        fun register() {
            adapter.registerData("createUser", mapOf("createUser" to kUserAliceJson))
        }

        @Test
        fun createUser_sendsNameInVariables() = runTest {
            client.mutations.createUser(minimalInput)
            @Suppress("UNCHECKED_CAST")
            val inputVar = adapter.getLastCall()!!.variables["input"] as Map<String, Any?>
            assertEquals("Alice Smith", inputVar["name"])
        }

        @Test
        fun createUser_sendsStatusAsString() = runTest {
            client.mutations.createUser(minimalInput)
            @Suppress("UNCHECKED_CAST")
            val inputVar = adapter.getLastCall()!!.variables["input"] as Map<String, Any?>
            assertEquals("ACTIVE", inputVar["status"])
        }

        @Test
        fun createUser_sendsAddressNested() = runTest {
            client.mutations.createUser(minimalInput)
            @Suppress("UNCHECKED_CAST")
            val inputVar = adapter.getLastCall()!!.variables["input"] as Map<String, Any?>
            @Suppress("UNCHECKED_CAST")
            val addrVar = inputVar["address"] as Map<String, Any?>
            assertEquals("Springfield", addrVar["city"])
        }

        @Test
        fun createUser_nullableFields_areNull_whenNotSet() = runTest {
            client.mutations.createUser(minimalInput)
            @Suppress("UNCHECKED_CAST")
            val inputVar = adapter.getLastCall()!!.variables["input"] as Map<String, Any?>
            assertNull(inputVar["priority"])
            assertNull(inputVar["billingAddress"])
            assertNull(inputVar["tags"])
        }

        @Test
        fun createUser_response_deserializesCorrectly() = runTest {
            val res = client.mutations.createUser(minimalInput)
            assertNotNull(res.createUser)
            assertEquals("user-1", res.createUser.id)
        }
    }

    // ── CreateUserInput — optional fields ─────────────────────────────────────

    @Nested
    inner class CreateUserInput_OptionalFields {

        @BeforeTest
        fun register() {
            adapter.registerData("createUser", mapOf("createUser" to kUserAliceJson))
        }

        @Test
        fun createUser_sendsPriority_whenSet() = runTest {
            val input = CreateUserInput(
                name = "Alice Smith", email = "alice@test.com",
                status = UserStatus.ACTIVE, address = kAddressInput,
                priority = Priority.HIGH,
            )
            client.mutations.createUser(input)
            @Suppress("UNCHECKED_CAST")
            val inputVar = adapter.getLastCall()!!.variables["input"] as Map<String, Any?>
            assertEquals("HIGH", inputVar["priority"])
        }

        @Test
        fun createUser_sendsTags_whenSet() = runTest {
            val input = CreateUserInput(
                name = "Alice Smith", email = "alice@test.com",
                status = UserStatus.ACTIVE, address = kAddressInput,
                tags = listOf("admin", "beta"),
            )
            client.mutations.createUser(input)
            @Suppress("UNCHECKED_CAST")
            val inputVar = adapter.getLastCall()!!.variables["input"] as Map<String, Any?>
            assertEquals(listOf("admin", "beta"), inputVar["tags"])
        }

        @Test
        fun createUser_sendsInitialScore_whenSet() = runTest {
            val input = CreateUserInput(
                name = "Alice Smith", email = "alice@test.com",
                status = UserStatus.ACTIVE, address = kAddressInput,
                initialScore = 100,
            )
            client.mutations.createUser(input)
            @Suppress("UNCHECKED_CAST")
            val inputVar = adapter.getLastCall()!!.variables["input"] as Map<String, Any?>
            assertEquals(100, (inputVar["initialScore"] as Number).toInt())
        }
    }

    // ── UpdateUserInput — all nullable fields ─────────────────────────────────

    @Nested
    inner class UpdateUserInput_AllNullable {

        @BeforeTest
        fun register() {
            adapter.registerData("updateUser", mapOf("updateUser" to kUserAliceJson))
        }

        @Test
        fun updateUser_emptyInput_sendsNullFields() = runTest {
            client.mutations.updateUser("user-1", UpdateUserInput())
            @Suppress("UNCHECKED_CAST")
            val inputVar = adapter.getLastCall()!!.variables["input"] as Map<String, Any?>
            assertNull(inputVar["name"])
            assertNull(inputVar["status"])
            assertNull(inputVar["priority"])
        }

        @Test
        fun updateUser_sendsIdInVariables() = runTest {
            client.mutations.updateUser("user-1", UpdateUserInput())
            assertEquals("user-1", adapter.getLastCall()!!.variables["id"])
        }

        @Test
        fun updateUser_withStatus_sendsStatusAsString() = runTest {
            client.mutations.updateUser("user-1", UpdateUserInput(status = UserStatus.SUSPENDED))
            @Suppress("UNCHECKED_CAST")
            val inputVar = adapter.getLastCall()!!.variables["input"] as Map<String, Any?>
            assertEquals("SUSPENDED", inputVar["status"])
        }

        @Test
        fun updateUser_response_deserializesCorrectly() = runTest {
            val res = client.mutations.updateUser("user-1", UpdateUserInput(name = "Alice Updated"))
            assertNotNull(res.updateUser)
        }
    }

    // ── AddressInput — nullable zip ───────────────────────────────────────────

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
