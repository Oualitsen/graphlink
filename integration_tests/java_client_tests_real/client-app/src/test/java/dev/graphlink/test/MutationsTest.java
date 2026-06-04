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

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class MutationsTest {

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
        client = newRealClient();
    }

    // ── createUser ────────────────────────────────────────────────────────────

    @Nested
    class CreateUser {

        @Test
        void response_returnsCreatedUser() {
            CreateUserResponse res = client.mutations.createUser(kCreateInput);
            assertNotNull(res.getCreateUser());
        }

        @Test
        void response_user_hasName() {
            CreateUserResponse res = client.mutations.createUser(kCreateInput);
            assertEquals("Alice Smith", res.getCreateUser().getName());
        }

        @Test
        void response_user_hasEmail() {
            CreateUserResponse res = client.mutations.createUser(kCreateInput);
            assertEquals("alice@test.com", res.getCreateUser().getEmail());
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

        @Test
        void response_returnsTrue() {
            DeleteUserResponse res = client.mutations.deleteUser("user-1");
            assertTrue(res.getDeleteUser());
        }
    }

    // ── updateUser ────────────────────────────────────────────────────────────

    @Nested
    class UpdateUser {

        @Test
        void response_returnsUpdatedUser() {
            UpdateUserInput input = UpdateUserInput.builder().name("Alice Updated").build();
            UpdateUserResponse res = client.mutations.updateUser("user-1", input);
            assertNotNull(res.getUpdateUser());
            assertEquals("user-1", res.getUpdateUser().getId());
        }

        @Test
        void response_user_hasUpdatedName() {
            UpdateUserInput input = UpdateUserInput.builder().name("Alice Updated").build();
            UpdateUserResponse res = client.mutations.updateUser("user-1", input);
            assertEquals("Alice Updated", res.getUpdateUser().getName());
        }

        @Test
        void response_user_statusUnchanged_whenNotInInput() {
            UpdateUserInput input = UpdateUserInput.builder().name("Alice Updated").build();
            UpdateUserResponse res = client.mutations.updateUser("user-1", input);
            assertEquals(UserStatus.ACTIVE, res.getUpdateUser().getStatus());
        }
    }

    // ── transferPost ──────────────────────────────────────────────────────────

    @Nested
    class TransferPost {

        @Test
        void response_returnsPost() {
            TransferPostResponse res = client.mutations.transferPost("post-1", "user-2");
            assertNotNull(res.getTransferPost());
            assertEquals("post-1", res.getTransferPost().getId());
        }

        @Test
        void response_post_authorIsNewOwner() {
            TransferPostResponse res = client.mutations.transferPost("post-1", "user-2");
            assertEquals("user-2", res.getTransferPost().getAuthor().getId());
        }
    }

    // ── resetAll ──────────────────────────────────────────────────────────────

    @Nested
    class ResetAll {

        @Test
        void response_returnsTrue() {
            ResetAllResponse res = client.mutations.resetAll();
            assertTrue(res.getResetAll());
        }
    }
}
