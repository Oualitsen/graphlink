package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.enums.Priority;
import dev.graphlink.test.generated.enums.UserStatus;
import dev.graphlink.test.generated.inputs.AddressInput;
import dev.graphlink.test.generated.inputs.CreateUserInput;
import dev.graphlink.test.generated.inputs.UpdateUserInput;
import dev.graphlink.test.generated.types.CreateUserResponse;
import dev.graphlink.test.generated.types.UpdateUserResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.List;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class InputsTest {

    private GraphLinkClient client;

    private static final AddressInput kAddressInput = AddressInput.builder()
            .street("123 Main St")
            .city("Springfield")
            .country("US")
            .zip("12345")
            .build();

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    // ── CreateUserInput — required fields ─────────────────────────────────────

    @Nested
    class CreateUserInput_RequiredFields {

        @Test
        void createUser_response_deserializesCorrectly() {
            CreateUserInput input = CreateUserInput.builder()
                    .name("Alice Smith")
                    .email("alice@test.com")
                    .status(UserStatus.ACTIVE)
                    .address(kAddressInput)
                    .build();
            CreateUserResponse res = client.mutations.createUser(input).block();
            assertNotNull(res.getCreateUser());
            assertEquals("Alice Smith", res.getCreateUser().getName());
        }

        @Test
        void createUser_address_isReflectedInResponse() {
            CreateUserInput input = CreateUserInput.builder()
                    .name("Alice Smith")
                    .email("alice@test.com")
                    .status(UserStatus.ACTIVE)
                    .address(kAddressInput)
                    .build();
            CreateUserResponse res = client.mutations.createUser(input).block();
            assertNotNull(res.getCreateUser().getAddress());
            assertEquals("Springfield", res.getCreateUser().getAddress().getCity());
        }

        @Test
        void createUser_status_isReflectedInResponse() {
            CreateUserInput input = CreateUserInput.builder()
                    .name("Alice Smith")
                    .email("alice@test.com")
                    .status(UserStatus.ACTIVE)
                    .address(kAddressInput)
                    .build();
            CreateUserResponse res = client.mutations.createUser(input).block();
            assertEquals(UserStatus.ACTIVE, res.getCreateUser().getStatus());
        }
    }

    // ── CreateUserInput — optional fields ─────────────────────────────────────

    @Nested
    class CreateUserInput_OptionalFields {

        @Test
        void createUser_withPriority_isReflectedInResponse() {
            CreateUserInput input = CreateUserInput.builder()
                    .name("Alice Smith")
                    .email("alice@test.com")
                    .status(UserStatus.ACTIVE)
                    .address(kAddressInput)
                    .priority(Priority.HIGH)
                    .build();
            CreateUserResponse res = client.mutations.createUser(input).block();
            assertEquals(Priority.HIGH, res.getCreateUser().getPriority());
        }
    }

    // ── UpdateUserInput — all nullable fields ─────────────────────────────────

    @Nested
    class UpdateUserInput_AllNullable {

        @Test
        void updateUser_response_deserializesCorrectly() {
            UpdateUserInput input = UpdateUserInput.builder().name("Alice Updated").build();
            UpdateUserResponse res = client.mutations.updateUser("user-1", input).block();
            assertNotNull(res.getUpdateUser());
            assertEquals("Alice Updated", res.getUpdateUser().getName());
        }

        @Test
        void updateUser_statusNotInInput_preservesOriginalStatus() {
            UpdateUserInput input = UpdateUserInput.builder().name("Alice Updated").build();
            UpdateUserResponse res = client.mutations.updateUser("user-1", input).block();
            assertEquals(UserStatus.ACTIVE, res.getUpdateUser().getStatus());
        }
    }

    // ── AddressInput — nullable zip (pure unit tests, no server needed) ────────

    @Nested
    class AddressInput_NullableZip {

        @Test
        void addressInput_zip_isNull_whenNotSet() {
            AddressInput addr = AddressInput.builder()
                    .street("1 Road")
                    .city("Town")
                    .country("US")
                    .build();
            assertNull(addr.getZip());
        }

        @Test
        void addressInput_zip_isPresent_whenSet() {
            AddressInput addr = AddressInput.builder()
                    .street("1 Road")
                    .city("Town")
                    .country("US")
                    .zip("00001")
                    .build();
            assertEquals("00001", addr.getZip());
        }
    }
}
