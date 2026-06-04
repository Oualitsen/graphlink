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
import dev.graphlink.test.Fixtures.newRealClient

class ErrorCaptureTest {

    private lateinit var client: GraphLinkClient

    private val kAddress = AddressInput("1 Main St", "Springfield", "US", "12345")
    private val kCreateInput = CreateUserInput(
        name = "Alice", email = "alice@test.com",
        status = UserStatus.ACTIVE, address = kAddress,
    )
    private val kErrorInput = CreateUserInput(
        name = "error-user", email = "e@test.com",
        status = UserStatus.ACTIVE, address = kAddress,
    )

    @BeforeTest
    fun setUp() {
        client = newRealClient()
    }

    // ── getUserOrErrors — success ──────────────────────────────────────────────

    @Nested
    inner class GetUserOrErrorsSuccess {

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
            client.queries.getUserOrErrors("user-1")
        }
    }

    // ── getUserOrErrors — server-side error (unknown id) ──────────────────────

    @Nested
    inner class GetUserOrErrorsWithErrors {

        @Test
        fun doesNotThrow_whenServerReturnsError() = runTest {
            client.queries.getUserOrErrors("unknown-id")
        }

        @Test
        fun errors_isNonEmpty_forUnknownId() = runTest {
            val res: GetUserOrErrorsFullResponse = client.queries.getUserOrErrors("unknown-id")
            assertNotNull(res.errors)
            assertTrue(res.errors!!.isNotEmpty())
        }

        @Test
        fun errors_hasMessage_forUnknownId() = runTest {
            val res = client.queries.getUserOrErrors("unknown-id")
            val msg = res.errors!![0].message
            assertNotNull(msg)
            assertTrue(msg.isNotBlank())
        }
    }

    // ── findUserOrErrors — null return (no error) ─────────────────────────────

    @Nested
    inner class FindUserOrErrorsNullReturn {

        @Test
        fun doesNotThrow_forUnknownId() = runTest {
            client.queries.findUserOrErrors("user-99")
        }

        @Test
        fun data_fieldIsNull_forUnknownId() = runTest {
            val res: FindUserOrErrorsFullResponse = client.queries.findUserOrErrors("user-99")
            assertTrue(res.data == null || res.data!!.findUserOrErrors == null)
        }

        @Test
        fun errors_isNullOrEmpty_forUnknownId() = runTest {
            val res = client.queries.findUserOrErrors("user-99")
            assertTrue(res.errors == null || res.errors!!.isEmpty())
        }
    }

    // ── findUserOrErrors — server error ───────────────────────────────────────

    @Nested
    inner class FindUserOrErrorsWithErrors {

        @Test
        fun doesNotThrow_forErrorId() = runTest {
            client.queries.findUserOrErrors("error-id")
        }

        @Test
        fun errors_isNonEmpty_forErrorId() = runTest {
            val res: FindUserOrErrorsFullResponse = client.queries.findUserOrErrors("error-id")
            assertNotNull(res.errors)
            assertTrue(res.errors!!.isNotEmpty())
        }
    }

    // ── findUserOrErrors — success ────────────────────────────────────────────

    @Nested
    inner class FindUserOrErrorsSuccess {

        @Test
        fun data_isPresent_forKnownId() = runTest {
            val res: FindUserOrErrorsFullResponse = client.queries.findUserOrErrors("user-1")
            assertNotNull(res.data)
            assertNotNull(res.data!!.findUserOrErrors)
            assertEquals("user-1", res.data!!.findUserOrErrors!!.id)
        }
    }

    // ── Non-captureErrors query throws on server error ────────────────────────

    @Nested
    inner class NonCaptureErrorsThrows {

        @Test
        fun getUser_throws_forUnknownId() = runTest {
            assertFailsWith<Exception> {
                client.queries.getUser("unknown-id")
            }
        }
    }

    // ── createUserOrErrors mutation ───────────────────────────────────────────

    @Nested
    inner class CreateUserOrErrorsMutation {

        @Test
        fun success_dataIsPresent() = runTest {
            val res: CreateUserOrErrorsFullResponse = client.mutations.createUserOrErrors(kCreateInput)
            assertNotNull(res.data)
            assertNotNull(res.data!!.createUserOrErrors)
        }

        @Test
        fun success_noErrors() = runTest {
            val res = client.mutations.createUserOrErrors(kCreateInput)
            assertTrue(res.errors == null || res.errors!!.isEmpty())
        }

        @Test
        fun doesNotThrow_whenServerReturnsError() = runTest {
            client.mutations.createUserOrErrors(kErrorInput)
        }

        @Test
        fun errors_arePopulated_whenServerReturnsError() = runTest {
            val res: CreateUserOrErrorsFullResponse = client.mutations.createUserOrErrors(kErrorInput)
            assertNotNull(res.errors)
            assertTrue(res.errors!!.isNotEmpty())
        }
    }
}
