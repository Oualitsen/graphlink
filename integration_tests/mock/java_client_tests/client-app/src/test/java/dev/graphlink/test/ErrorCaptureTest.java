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

import java.util.List;
import java.util.Map;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class ErrorCaptureTest {

    private MockAdapter adapter;
    private GraphLinkClient client;

    private static final AddressInput kAddress = AddressInput.builder()
            .street("1 Main St").city("Springfield").country("US").zip("12345").build();
    private static final CreateUserInput kCreateInput = CreateUserInput.builder()
            .name("Alice").email("alice@test.com").status(UserStatus.ACTIVE).address(kAddress).build();

    @BeforeEach
    void setUp() {
        adapter = new MockAdapter();
        client = newClient(adapter, new MockWebSocketAdapter());
    }

    // ── getUserOrErrors — success (data, no errors) ────────────────────────────

    @Nested
    class GetUserOrErrorsSuccess {

        @BeforeEach
        void register() {
            adapter.registerData("getUserOrErrors", Map.of("getUserOrErrors", kUserAliceJson));
        }

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

    // ── getUserOrErrors — errors alongside data (partial success) ──────────────

    @Nested
    class GetUserOrErrorsWithErrors {

        @BeforeEach
        void register() {
            adapter.registerDataAndErrors(
                    "getUserOrErrors",
                    Map.of("getUserOrErrors", kUserAliceJson),
                    List.of(kGraphQLError)
            );
        }

        @Test
        void doesNotThrow_whenErrorsPresent() {
            assertDoesNotThrow(() -> client.queries.getUserOrErrors("user-1"));
        }

        @Test
        void data_isStillPresent_whenErrorsPresent() {
            GetUserOrErrorsFullResponse res = client.queries.getUserOrErrors("user-1");
            assertNotNull(res.getData());
            assertNotNull(res.getData().getGetUserOrErrors());
        }

        @Test
        void errors_isNonEmpty() {
            GetUserOrErrorsFullResponse res = client.queries.getUserOrErrors("user-1");
            assertNotNull(res.getErrors());
            assertFalse(res.getErrors().isEmpty());
        }

        @Test
        void errors_firstMessage_isCorrect() {
            GetUserOrErrorsFullResponse res = client.queries.getUserOrErrors("user-1");
            assertEquals("Not found", res.getErrors().get(0).getMessage());
        }
    }

    // ── getUserOrErrors — full error (data: null) ──────────────────────────────

    @Nested
    class GetUserOrErrorsNullData {

        @BeforeEach
        void register() {
            adapter.registerErrors("getUserOrErrors", List.of(kGraphQLError));
        }

        @Test
        void doesNotThrow_whenDataNull() {
            assertDoesNotThrow(() -> client.queries.getUserOrErrors("user-1"));
        }

        @Test
        void data_isNull() {
            GetUserOrErrorsFullResponse res = client.queries.getUserOrErrors("user-1");
            assertNull(res.getData());
        }

        @Test
        void errors_isNonEmpty() {
            GetUserOrErrorsFullResponse res = client.queries.getUserOrErrors("user-1");
            assertNotNull(res.getErrors());
            assertFalse(res.getErrors().isEmpty());
        }
    }

    // ── findUserOrErrors — nullable return, errors with null data ─────────────

    @Nested
    class FindUserOrErrorsWithErrors {

        @BeforeEach
        void register() {
            adapter.registerErrors("findUserOrErrors", List.of(kGraphQLError));
        }

        @Test
        void doesNotThrow() {
            assertDoesNotThrow(() -> client.queries.findUserOrErrors("user-1"));
        }

        @Test
        void data_fieldIsNull() {
            FindUserOrErrorsFullResponse res = client.queries.findUserOrErrors("user-1");
            // data wrapper may be null (data:null) or the field itself null
            assertTrue(res.getData() == null
                    || res.getData().getFindUserOrErrors() == null);
        }

        @Test
        void errors_isNonEmpty() {
            FindUserOrErrorsFullResponse res = client.queries.findUserOrErrors("user-1");
            assertNotNull(res.getErrors());
            assertFalse(res.getErrors().isEmpty());
        }

        @Test
        void errors_message_isCorrect() {
            assertEquals("Not found",
                    client.queries.findUserOrErrors("user-1").getErrors().get(0).getMessage());
        }
    }

    // ── findUserOrErrors — success ────────────────────────────────────────────

    @Nested
    class FindUserOrErrorsSuccess {

        @Test
        void data_isPresent_whenNoErrors() {
            adapter.registerData("findUserOrErrors", Map.of("findUserOrErrors", kUserAliceJson));
            FindUserOrErrorsFullResponse res = client.queries.findUserOrErrors("user-1");
            assertNotNull(res.getData());
            assertNotNull(res.getData().getFindUserOrErrors());
            assertEquals("user-1", res.getData().getFindUserOrErrors().getId());
        }
    }

    // ── Non-captureErrors query throws on errors ───────────────────────────────

    @Nested
    class NonCaptureErrorsThrows {

        @Test
        void getUser_throws_whenResponseHasErrors() {
            adapter.registerDataAndErrors(
                    "getUser",
                    Map.of("getUser", kUserAliceJson),
                    List.of(kGraphQLError)
            );
            assertThrows(RuntimeException.class, () -> client.queries.getUser("user-1"));
        }
    }

    // ── createUserOrErrors mutation — error capture ────────────────────────────

    @Nested
    class CreateUserOrErrorsMutation {

        @Test
        void doesNotThrow_whenErrorsPresent() {
            adapter.registerDataAndErrors(
                    "createUserOrErrors",
                    Map.of("createUserOrErrors", kUserAliceJson),
                    List.of(kGraphQLError)
            );
            assertDoesNotThrow(() -> client.mutations.createUserOrErrors(kCreateInput));
        }

        @Test
        void data_isPresent_alongside_errors() {
            adapter.registerDataAndErrors(
                    "createUserOrErrors",
                    Map.of("createUserOrErrors", kUserAliceJson),
                    List.of(kGraphQLError)
            );
            CreateUserOrErrorsFullResponse res = client.mutations.createUserOrErrors(kCreateInput);
            assertNotNull(res.getData());
            assertNotNull(res.getData().getCreateUserOrErrors());
        }

        @Test
        void errors_arePopulated() {
            adapter.registerDataAndErrors(
                    "createUserOrErrors",
                    Map.of("createUserOrErrors", kUserAliceJson),
                    List.of(kGraphQLError)
            );
            CreateUserOrErrorsFullResponse res = client.mutations.createUserOrErrors(kCreateInput);
            assertFalse(res.getErrors().isEmpty());
        }

        @Test
        void success_noErrors_dataIsPresent() {
            adapter.registerData("createUserOrErrors",
                    Map.of("createUserOrErrors", kUserAliceJson));
            CreateUserOrErrorsFullResponse res = client.mutations.createUserOrErrors(kCreateInput);
            assertNotNull(res.getData().getCreateUserOrErrors());
            assertTrue(res.getErrors() == null || res.getErrors().isEmpty());
        }
    }
}
