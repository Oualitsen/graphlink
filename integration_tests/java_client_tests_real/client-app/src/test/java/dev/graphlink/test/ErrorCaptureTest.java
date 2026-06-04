package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.types.CreateUserOrErrorsFullResponse;
import dev.graphlink.test.generated.types.FindUserOrErrorsFullResponse;
import dev.graphlink.test.generated.types.GetUserOrErrorsFullResponse;
import dev.graphlink.test.generated.inputs.AddressInput;
import dev.graphlink.test.generated.inputs.CreateUserInput;
import dev.graphlink.test.generated.enums.UserStatus;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class ErrorCaptureTest {

    private GraphLinkClient client;

    private static final AddressInput kAddress = AddressInput.builder()
            .street("1 Main St").city("Springfield").country("US").zip("12345").build();
    private static final CreateUserInput kCreateInput = CreateUserInput.builder()
            .name("Alice").email("alice@test.com").status(UserStatus.ACTIVE).address(kAddress).build();
    private static final CreateUserInput kErrorInput = CreateUserInput.builder()
            .name("error-user").email("e@test.com").status(UserStatus.ACTIVE).address(kAddress).build();

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    // ── getUserOrErrors — success ──────────────────────────────────────────────

    @Nested
    class GetUserOrErrorsSuccess {

        @Test
        void returnsFullResponse() {
            assertNotNull(client.queries.getUserOrErrors("user-1"));
        }

        @Test
        void data_isNotNull() {
            assertNotNull(client.queries.getUserOrErrors("user-1").getData());
        }

        @Test
        void data_user_hasCorrectId() {
            assertEquals("user-1",
                    client.queries.getUserOrErrors("user-1").getData().getGetUserOrErrors().getId());
        }

        @Test
        void errors_isNullOrEmpty_onSuccess() {
            GetUserOrErrorsFullResponse res = client.queries.getUserOrErrors("user-1");
            assertTrue(res.getErrors() == null || res.getErrors().isEmpty());
        }

        @Test
        void doesNotThrow_onSuccess() {
            assertDoesNotThrow(() -> client.queries.getUserOrErrors("user-1"));
        }
    }

    // ── getUserOrErrors — server-side GraphQL error (unknown id) ──────────────

    @Nested
    class GetUserOrErrorsWithErrors {

        @Test
        void doesNotThrow_whenServerReturnsError() {
            assertDoesNotThrow(() -> client.queries.getUserOrErrors("unknown-id"));
        }

        @Test
        void errors_isNonEmpty_forUnknownId() {
            GetUserOrErrorsFullResponse res = client.queries.getUserOrErrors("unknown-id");
            assertNotNull(res.getErrors());
            assertFalse(res.getErrors().isEmpty());
        }

        @Test
        void errors_hasMessage_forUnknownId() {
            GetUserOrErrorsFullResponse res = client.queries.getUserOrErrors("unknown-id");
            assertNotNull(res.getErrors().get(0).getMessage());
            assertFalse(res.getErrors().get(0).getMessage().isBlank());
        }
    }

    // ── findUserOrErrors — null return (non-error) ────────────────────────────

    @Nested
    class FindUserOrErrorsNullReturn {

        @Test
        void doesNotThrow_forUnknownId() {
            assertDoesNotThrow(() -> client.queries.findUserOrErrors("user-99"));
        }

        @Test
        void data_fieldIsNull_forUnknownId() {
            FindUserOrErrorsFullResponse res = client.queries.findUserOrErrors("user-99");
            assertTrue(res.getData() == null
                    || res.getData().getFindUserOrErrors() == null);
        }

        @Test
        void errors_isNullOrEmpty_forUnknownId() {
            FindUserOrErrorsFullResponse res = client.queries.findUserOrErrors("user-99");
            assertTrue(res.getErrors() == null || res.getErrors().isEmpty());
        }
    }

    // ── findUserOrErrors — server error ───────────────────────────────────────

    @Nested
    class FindUserOrErrorsWithErrors {

        @Test
        void doesNotThrow_forErrorId() {
            assertDoesNotThrow(() -> client.queries.findUserOrErrors("error-id"));
        }

        @Test
        void errors_isNonEmpty_forErrorId() {
            FindUserOrErrorsFullResponse res = client.queries.findUserOrErrors("error-id");
            assertNotNull(res.getErrors());
            assertFalse(res.getErrors().isEmpty());
        }
    }

    // ── findUserOrErrors — success ────────────────────────────────────────────

    @Nested
    class FindUserOrErrorsSuccess {

        @Test
        void data_isPresent_forKnownId() {
            FindUserOrErrorsFullResponse res = client.queries.findUserOrErrors("user-1");
            assertNotNull(res.getData());
            assertNotNull(res.getData().getFindUserOrErrors());
            assertEquals("user-1", res.getData().getFindUserOrErrors().getId());
        }
    }

    // ── Non-captureErrors query throws on server error ────────────────────────

    @Nested
    class NonCaptureErrorsThrows {

        @Test
        void getUser_throws_forUnknownId() {
            assertThrows(RuntimeException.class, () -> client.queries.getUser("unknown-id"));
        }
    }

    // ── createUserOrErrors mutation ───────────────────────────────────────────

    @Nested
    class CreateUserOrErrorsMutation {

        @Test
        void success_dataIsPresent() {
            CreateUserOrErrorsFullResponse res = client.mutations.createUserOrErrors(kCreateInput);
            assertNotNull(res.getData());
            assertNotNull(res.getData().getCreateUserOrErrors());
        }

        @Test
        void success_noErrors() {
            CreateUserOrErrorsFullResponse res = client.mutations.createUserOrErrors(kCreateInput);
            assertTrue(res.getErrors() == null || res.getErrors().isEmpty());
        }

        @Test
        void doesNotThrow_whenServerReturnsError() {
            assertDoesNotThrow(() -> client.mutations.createUserOrErrors(kErrorInput));
        }

        @Test
        void errors_arePopulated_whenServerReturnsError() {
            CreateUserOrErrorsFullResponse res = client.mutations.createUserOrErrors(kErrorInput);
            assertNotNull(res.getErrors());
            assertFalse(res.getErrors().isEmpty());
        }
    }
}
