package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.UserStatus
import dev.graphlink.test.generated.inputs.AddressInput
import dev.graphlink.test.generated.inputs.CreateUserInput
import dev.graphlink.test.generated.types.CreateUserOrErrorsFullResponse
import dev.graphlink.test.generated.types.FindUserOrErrorsFullResponse
import dev.graphlink.test.generated.types.GetUserOrErrorsFullResponse
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.kGraphQLError
import dev.graphlink.test.Fixtures.kUserAliceJson
import dev.graphlink.test.Fixtures.newClient

class ErrorCaptureTest {

    private lateinit var adapter: MockAdapter
    private lateinit var client: GraphLinkClient

    private val kAddress = AddressInput("1 Main St", "Springfield", "US", "12345")
    private val kCreateInput = CreateUserInput(
        name = "Alice", email = "alice@test.com",
        status = UserStatus.ACTIVE, address = kAddress,
    )

    @BeforeTest
    fun setUp() {
        adapter = MockAdapter()
        client = newClient(adapter, MockWebSocketAdapter())
    }

    // ── getUserOrErrors — success ──────────────────────────────────────────────

    @Nested
    inner class GetUserOrErrorsSuccess {

        @BeforeTest
        fun register() {
            adapter.registerData("getUserOrErrors", mapOf("getUserOrErrors" to kUserAliceJson))
        }

        @Test
        fun returnsFullResponse() = runTest {
            assertNotNull(client.queries.getUserOrErrors("user-1"))
        }

        @Test
        fun data_isNotNull() = runTest {
            assertNotNull(client.queries.getUserOrErrors("user-1").data)
        }

        @Test
        fun data_user_hasCorrectId() = runTest {
            assertEquals("user-1",
                client.queries.getUserOrErrors("user-1").data!!.getUserOrErrors.id)
        }

        @Test
        fun errors_isNullOrEmpty_onSuccess() = runTest {
            val res: GetUserOrErrorsFullResponse = client.queries.getUserOrErrors("user-1")
            assertTrue(res.errors == null || res.errors!!.isEmpty())
        }

        @Test
        fun doesNotThrow_onSuccess() = runTest {
            client.queries.getUserOrErrors("user-1") // must not throw
        }
    }

    // ── getUserOrErrors — partial success (data + errors) ─────────────────────

    @Nested
    inner class GetUserOrErrorsWithErrors {

        @BeforeTest
        fun register() {
            adapter.registerDataAndErrors(
                "getUserOrErrors",
                mapOf("getUserOrErrors" to kUserAliceJson),
                listOf(kGraphQLError),
            )
        }

        @Test
        fun doesNotThrow_whenErrorsPresent() = runTest {
            client.queries.getUserOrErrors("user-1") // must not throw
        }

        @Test
        fun data_isStillPresent_whenErrorsPresent() = runTest {
            val res = client.queries.getUserOrErrors("user-1")
            assertNotNull(res.data)
            assertNotNull(res.data!!.getUserOrErrors)
        }

        @Test
        fun errors_isNonEmpty() = runTest {
            val res = client.queries.getUserOrErrors("user-1")
            assertNotNull(res.errors)
            assertTrue(res.errors!!.isNotEmpty())
        }

        @Test
        fun errors_firstMessage_isCorrect() = runTest {
            val res = client.queries.getUserOrErrors("user-1")
            assertEquals("Not found", res.errors!![0].message)
        }
    }

    // ── getUserOrErrors — full error (data: null) ──────────────────────────────

    @Nested
    inner class GetUserOrErrorsNullData {

        @BeforeTest
        fun register() {
            adapter.registerErrors("getUserOrErrors", listOf(kGraphQLError))
        }

        @Test
        fun doesNotThrow_whenDataNull() = runTest {
            client.queries.getUserOrErrors("user-1") // must not throw
        }

        @Test
        fun data_isNull() = runTest {
            val res: GetUserOrErrorsFullResponse = client.queries.getUserOrErrors("user-1")
            assertNull(res.data)
        }

        @Test
        fun errors_isNonEmpty() = runTest {
            val res = client.queries.getUserOrErrors("user-1")
            assertNotNull(res.errors)
            assertTrue(res.errors!!.isNotEmpty())
        }
    }

    // ── findUserOrErrors — nullable return ────────────────────────────────────

    @Nested
    inner class FindUserOrErrorsWithErrors {

        @BeforeTest
        fun register() {
            adapter.registerErrors("findUserOrErrors", listOf(kGraphQLError))
        }

        @Test
        fun doesNotThrow() = runTest {
            client.queries.findUserOrErrors("user-1") // must not throw
        }

        @Test
        fun data_fieldIsNull() = runTest {
            val res: FindUserOrErrorsFullResponse = client.queries.findUserOrErrors("user-1")
            assertTrue(res.data == null || res.data!!.findUserOrErrors == null)
        }

        @Test
        fun errors_isNonEmpty() = runTest {
            val res = client.queries.findUserOrErrors("user-1")
            assertNotNull(res.errors)
            assertTrue(res.errors!!.isNotEmpty())
        }

        @Test
        fun errors_message_isCorrect() = runTest {
            assertEquals("Not found",
                client.queries.findUserOrErrors("user-1").errors!![0].message)
        }
    }

    // ── findUserOrErrors — success ────────────────────────────────────────────

    @Nested
    inner class FindUserOrErrorsSuccess {

        @Test
        fun data_isPresent_whenNoErrors() = runTest {
            adapter.registerData("findUserOrErrors", mapOf("findUserOrErrors" to kUserAliceJson))
            val res = client.queries.findUserOrErrors("user-1")
            assertNotNull(res.data)
            assertNotNull(res.data!!.findUserOrErrors)
            assertEquals("user-1", res.data!!.findUserOrErrors!!.id)
        }
    }

    // ── Non-captureErrors query throws on errors ───────────────────────────────

    @Nested
    inner class NonCaptureErrorsThrows {

        @Test
        fun getUser_throws_whenResponseHasErrors() = runTest {
            adapter.registerDataAndErrors(
                "getUser",
                mapOf("getUser" to kUserAliceJson),
                listOf(kGraphQLError),
            )
            assertFailsWith<Exception> {
                client.queries.getUser("user-1")
            }
        }
    }

    // ── createUserOrErrors mutation ────────────────────────────────────────────

    @Nested
    inner class CreateUserOrErrorsMutation {

        @Test
        fun doesNotThrow_whenErrorsPresent() = runTest {
            adapter.registerDataAndErrors(
                "createUserOrErrors",
                mapOf("createUserOrErrors" to kUserAliceJson),
                listOf(kGraphQLError),
            )
            client.mutations.createUserOrErrors(kCreateInput) // must not throw
        }

        @Test
        fun data_isPresent_alongside_errors() = runTest {
            adapter.registerDataAndErrors(
                "createUserOrErrors",
                mapOf("createUserOrErrors" to kUserAliceJson),
                listOf(kGraphQLError),
            )
            val res: CreateUserOrErrorsFullResponse = client.mutations.createUserOrErrors(kCreateInput)
            assertNotNull(res.data)
            assertNotNull(res.data!!.createUserOrErrors)
        }

        @Test
        fun errors_arePopulated() = runTest {
            adapter.registerDataAndErrors(
                "createUserOrErrors",
                mapOf("createUserOrErrors" to kUserAliceJson),
                listOf(kGraphQLError),
            )
            val res = client.mutations.createUserOrErrors(kCreateInput)
            assertTrue(res.errors!!.isNotEmpty())
        }

        @Test
        fun success_noErrors_dataIsPresent() = runTest {
            adapter.registerData("createUserOrErrors", mapOf("createUserOrErrors" to kUserAliceJson))
            val res = client.mutations.createUserOrErrors(kCreateInput)
            assertNotNull(res.data!!.createUserOrErrors)
            assertTrue(res.errors == null || res.errors!!.isEmpty())
        }
    }
}
