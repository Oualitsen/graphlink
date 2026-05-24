package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.enums.UserStatus;
import dev.graphlink.test.generated.inputs.AddressInput;
import dev.graphlink.test.generated.inputs.CreateUserInput;
import dev.graphlink.test.generated.inputs.UpdateUserInput;
import dev.graphlink.test.generated.types.CreateUserResponse;
import dev.graphlink.test.generated.types.DeleteUserResponse;
import dev.graphlink.test.generated.types.ResetAllResponse;
import dev.graphlink.test.generated.types.TransferPostResponse;
import dev.graphlink.test.generated.types.UpdateUserResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class MutationsTest {

    private MockAdapter adapter;
    private GraphLinkClient client;

    private static final AddressInput kAddressInput = AddressInput.builder()
            .street("123 Main St")
            .city("Springfield")
            .country("US")
            .zip("12345")
            .build();

    private static final CreateUserInput kCreateInput = CreateUserInput.builder()
            .name("Alice Smith")
            .email("alice@test.com")
            .status(UserStatus.ACTIVE)
            .address(kAddressInput)
            .build();

    @BeforeEach
    void setUp() {
        adapter = new MockAdapter();
        client = newClient(adapter, new MockWebSocketAdapter());
    }

    // ── createUser ────────────────────────────────────────────────────────────

    @Nested
    class CreateUser {

        @BeforeEach
        void register() {
            adapter.registerData("createUser", Map.of("createUser", kUserAliceJson));
        }

        @Test
        void operationName_isCreateUser() {
            client.mutations.createUser(kCreateInput);
            assertEquals("createUser", adapter.getLastCall().operationName());
        }

        @Test
        void inputObject_isSentAsVariables() {
            client.mutations.createUser(kCreateInput);
            assertNotNull(adapter.getLastCall().variables().get("input"));
        }

        @Test
        void response_returnsCreatedUser() {
            CreateUserResponse res = client.mutations.createUser(kCreateInput);
            assertNotNull(res.getCreateUser());
            assertEquals("user-1", res.getCreateUser().getId());
        }

        @Test
        void response_user_hasCorrectStatus() {
            CreateUserResponse res = client.mutations.createUser(kCreateInput);
            assertEquals(UserStatus.ACTIVE, res.getCreateUser().getStatus());
        }

        @Test
        void response_user_hasNestedAddress() {
            CreateUserResponse res = client.mutations.createUser(kCreateInput);
            assertNotNull(res.getCreateUser().getAddress());
            assertEquals("Springfield", res.getCreateUser().getAddress().getCity());
        }
    }

    // ── deleteUser ────────────────────────────────────────────────────────────

    @Nested
    class DeleteUser {

        @BeforeEach
        void register() {
            adapter.registerData("deleteUser", Map.of("deleteUser", true));
        }

        @Test
        void operationName_isDeleteUser() {
            client.mutations.deleteUser("user-1");
            assertEquals("deleteUser", adapter.getLastCall().operationName());
        }

        @Test
        void idArgument_isSentInVariables() {
            client.mutations.deleteUser("user-1");
            assertEquals("user-1", adapter.getLastCall().variables().get("id"));
        }

        @Test
        void response_returnsTrue() {
            DeleteUserResponse res = client.mutations.deleteUser("user-1");
            assertTrue(res.getDeleteUser());
        }
    }

    // ── updateUser ────────────────────────────────────────────────────────────

    @Nested
    class UpdateUser {

        @BeforeEach
        void register() {
            adapter.registerData("updateUser", Map.of("updateUser", kUserAliceJson));
        }

        @Test
        void operationName_isUpdateUser() {
            UpdateUserInput input = UpdateUserInput.builder().name("Alice Updated").build();
            client.mutations.updateUser("user-1", input);
            assertEquals("updateUser", adapter.getLastCall().operationName());
        }

        @Test
        void idAndInput_areSentInVariables() {
            UpdateUserInput input = UpdateUserInput.builder().name("Alice Updated").build();
            client.mutations.updateUser("user-1", input);
            assertEquals("user-1", adapter.getLastCall().variables().get("id"));
            assertNotNull(adapter.getLastCall().variables().get("input"));
        }

        @Test
        void response_returnsUpdatedUser() {
            UpdateUserInput input = UpdateUserInput.builder().status(UserStatus.INACTIVE).build();
            UpdateUserResponse res = client.mutations.updateUser("user-1", input);
            assertNotNull(res.getUpdateUser());
            assertEquals("user-1", res.getUpdateUser().getId());
        }

        @Test
        void nullableField_inInput_isSentAsNull() {
            UpdateUserInput input = UpdateUserInput.builder().build();
            client.mutations.updateUser("user-1", input);
            @SuppressWarnings("unchecked")
            Map<String, Object> inputVar = (Map<String, Object>) adapter.getLastCall().variables().get("input");
            assertNull(inputVar.get("status"));
        }
    }

    // ── transferPost ──────────────────────────────────────────────────────────

    @Nested
    class TransferPost {

        @BeforeEach
        void register() {
            adapter.registerData("transferPost", Map.of("transferPost", kPostJson));
        }

        @Test
        void operationName_isTransferPost() {
            client.mutations.transferPost("post-1", "user-2");
            assertEquals("transferPost", adapter.getLastCall().operationName());
        }

        @Test
        void bothArgs_areSentInVariables() {
            client.mutations.transferPost("post-1", "user-2");
            assertEquals("post-1", adapter.getLastCall().variables().get("postId"));
            assertEquals("user-2", adapter.getLastCall().variables().get("newAuthorId"));
        }

        @Test
        void response_returnsPost() {
            TransferPostResponse res = client.mutations.transferPost("post-1", "user-2");
            assertNotNull(res.getTransferPost());
            assertEquals("post-1", res.getTransferPost().getId());
        }
    }

    // ── resetAll (Boolean return, no args) ────────────────────────────────────

    @Nested
    class ResetAll {

        @BeforeEach
        void register() {
            adapter.registerData("resetAll", Map.of("resetAll", true));
        }

        @Test
        void operationName_isResetAll() {
            client.mutations.resetAll();
            assertEquals("resetAll", adapter.getLastCall().operationName());
        }

        @Test
        void response_returnsTrue() {
            ResetAllResponse res = client.mutations.resetAll();
            assertTrue(res.getResetAll());
        }
    }

    // ── Call count sanity ─────────────────────────────────────────────────────

    @Nested
    class CallCount {

        @Test
        void eachMutationCallIsRecorded() {
            adapter.registerData("createUser", Map.of("createUser", kUserAliceJson));
            adapter.registerData("deleteUser", Map.of("deleteUser", true));
            client.mutations.createUser(kCreateInput);
            client.mutations.deleteUser("user-1");
            assertEquals(2, adapter.getCallCount());
        }
    }
}
