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
import java.util.Map;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class InputsTest {

    private MockAdapter adapter;
    private GraphLinkClient client;

    private static final AddressInput kAddressInput = AddressInput.builder()
            .street("123 Main St")
            .city("Springfield")
            .country("US")
            .zip("12345")
            .build();

    @BeforeEach
    void setUp() {
        adapter = new MockAdapter();
        client = newClient(adapter, new MockWebSocketAdapter());
    }

    // ── CreateUserInput — required fields ─────────────────────────────────────

    @Nested
    class CreateUserInput_RequiredFields {

        private CreateUserInput minimalInput;

        @BeforeEach
        void setup() {
            adapter.registerData("createUser", Map.of("createUser", kUserAliceJson));
            minimalInput = CreateUserInput.builder()
                    .name("Alice Smith")
                    .email("alice@test.com")
                    .status(UserStatus.ACTIVE)
                    .address(kAddressInput)
                    .build();
        }

        @Test
        void createUser_sendsNameInVariables() {
            client.mutations.createUser(minimalInput);
            @SuppressWarnings("unchecked")
            Map<String, Object> inputVar = (Map<String, Object>) adapter.getLastCall().variables().get("input");
            assertEquals("Alice Smith", inputVar.get("name"));
        }

        @Test
        void createUser_sendsStatusAsString() {
            client.mutations.createUser(minimalInput);
            @SuppressWarnings("unchecked")
            Map<String, Object> inputVar = (Map<String, Object>) adapter.getLastCall().variables().get("input");
            assertEquals("ACTIVE", inputVar.get("status"));
        }

        @Test
        void createUser_sendsAddressNested() {
            client.mutations.createUser(minimalInput);
            @SuppressWarnings("unchecked")
            Map<String, Object> inputVar = (Map<String, Object>) adapter.getLastCall().variables().get("input");
            @SuppressWarnings("unchecked")
            Map<String, Object> addrVar = (Map<String, Object>) inputVar.get("address");
            assertEquals("Springfield", addrVar.get("city"));
        }

        @Test
        void createUser_nullableFields_areNull_whenNotSet() {
            client.mutations.createUser(minimalInput);
            @SuppressWarnings("unchecked")
            Map<String, Object> inputVar = (Map<String, Object>) adapter.getLastCall().variables().get("input");
            assertNull(inputVar.get("priority"));
            assertNull(inputVar.get("billingAddress"));
            assertNull(inputVar.get("tags"));
        }

        @Test
        void createUser_response_deserializesCorrectly() {
            CreateUserResponse res = client.mutations.createUser(minimalInput);
            assertNotNull(res.getCreateUser());
            assertEquals("user-1", res.getCreateUser().getId());
        }
    }

    // ── CreateUserInput — optional fields ─────────────────────────────────────

    @Nested
    class CreateUserInput_OptionalFields {

        @BeforeEach
        void register() {
            adapter.registerData("createUser", Map.of("createUser", kUserAliceJson));
        }

        @Test
        void createUser_sendsPriority_whenSet() {
            CreateUserInput input = CreateUserInput.builder()
                    .name("Alice Smith")
                    .email("alice@test.com")
                    .status(UserStatus.ACTIVE)
                    .address(kAddressInput)
                    .priority(Priority.HIGH)
                    .build();
            client.mutations.createUser(input);
            @SuppressWarnings("unchecked")
            Map<String, Object> inputVar = (Map<String, Object>) adapter.getLastCall().variables().get("input");
            assertEquals("HIGH", inputVar.get("priority"));
        }

        @Test
        void createUser_sendsTags_whenSet() {
            CreateUserInput input = CreateUserInput.builder()
                    .name("Alice Smith")
                    .email("alice@test.com")
                    .status(UserStatus.ACTIVE)
                    .address(kAddressInput)
                    .tags(List.of("admin", "beta"))
                    .build();
            client.mutations.createUser(input);
            @SuppressWarnings("unchecked")
            Map<String, Object> inputVar = (Map<String, Object>) adapter.getLastCall().variables().get("input");
            assertEquals(List.of("admin", "beta"), inputVar.get("tags"));
        }

        @Test
        void createUser_sendsInitialScore_whenSet() {
            CreateUserInput input = CreateUserInput.builder()
                    .name("Alice Smith")
                    .email("alice@test.com")
                    .status(UserStatus.ACTIVE)
                    .address(kAddressInput)
                    .initialScore(100)
                    .build();
            client.mutations.createUser(input);
            @SuppressWarnings("unchecked")
            Map<String, Object> inputVar = (Map<String, Object>) adapter.getLastCall().variables().get("input");
            assertEquals(100, inputVar.get("initialScore"));
        }
    }

    // ── UpdateUserInput — all nullable fields ─────────────────────────────────

    @Nested
    class UpdateUserInput_AllNullable {

        @BeforeEach
        void register() {
            adapter.registerData("updateUser", Map.of("updateUser", kUserAliceJson));
        }

        @Test
        void updateUser_emptyInput_sendsNullFields() {
            UpdateUserInput input = UpdateUserInput.builder().build();
            client.mutations.updateUser("user-1", input);
            @SuppressWarnings("unchecked")
            Map<String, Object> inputVar = (Map<String, Object>) adapter.getLastCall().variables().get("input");
            assertNull(inputVar.get("name"));
            assertNull(inputVar.get("status"));
            assertNull(inputVar.get("priority"));
        }

        @Test
        void updateUser_sendsIdInVariables() {
            UpdateUserInput input = UpdateUserInput.builder().build();
            client.mutations.updateUser("user-1", input);
            assertEquals("user-1", adapter.getLastCall().variables().get("id"));
        }

        @Test
        void updateUser_withStatus_sendsStatusAsString() {
            UpdateUserInput input = UpdateUserInput.builder()
                    .status(UserStatus.SUSPENDED)
                    .build();
            client.mutations.updateUser("user-1", input);
            @SuppressWarnings("unchecked")
            Map<String, Object> inputVar = (Map<String, Object>) adapter.getLastCall().variables().get("input");
            assertEquals("SUSPENDED", inputVar.get("status"));
        }

        @Test
        void updateUser_response_deserializesCorrectly() {
            UpdateUserInput input = UpdateUserInput.builder().name("Alice Updated").build();
            UpdateUserResponse res = client.mutations.updateUser("user-1", input);
            assertNotNull(res.getUpdateUser());
        }
    }

    // ── AddressInput — nullable zip ───────────────────────────────────────────

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
