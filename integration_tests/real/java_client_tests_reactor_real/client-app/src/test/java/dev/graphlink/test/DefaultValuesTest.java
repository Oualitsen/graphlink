package dev.graphlink.test;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.enums.Role;
import dev.graphlink.test.generated.inputs.AddressInput;
import dev.graphlink.test.generated.inputs.CreateWithDefaultsInput;
import dev.graphlink.test.generated.inputs.NestedDefaultsInput;
import dev.graphlink.test.generated.types.CreateWithDefaultsResponse;
import dev.graphlink.test.generated.types.CreateWithNestedDefaultsResponse;
import dev.graphlink.test.generated.types.ListUsersWithDefaultsResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static dev.graphlink.test.Fixtures.newRealClient;
import static org.junit.jupiter.api.Assertions.*;

class DefaultValuesTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    // ── listUsersWithDefaults — operation argument defaults ──────────────────

    @Nested
    class ListUsersWithDefaults {

        @Test
        void returnsUsers_withoutArguments() {
            ListUsersWithDefaultsResponse res = client.queries.listUsersWithDefaults(null, null).block();
            assertNotNull(res.getListUsersWithDefaults());
            assertFalse(res.getListUsersWithDefaults().isEmpty());
        }

        @Test
        void explicitLimit_overridesDefault() {
            ListUsersWithDefaultsResponse res = client.queries.listUsersWithDefaults(1, null).block();
            assertEquals(1, res.getListUsersWithDefaults().size());
        }

        @Test
        void explicitRole_canBeProvided() {
            ListUsersWithDefaultsResponse res = client.queries.listUsersWithDefaults(null, Role.ADMIN).block();
            assertFalse(res.getListUsersWithDefaults().isEmpty());
        }
    }

    // ── createWithDefaults — input field defaults ────────────────────────────

    @Nested
    class CreateWithDefaults {

        @Test
        void role_defaultsToUSER() {
            CreateWithDefaultsInput input = CreateWithDefaultsInput.builder().name("test").build();
            CreateWithDefaultsResponse res = client.mutations.createWithDefaults(input).block();
            assertEquals(Role.USER, res.getCreateWithDefaults().getRole());
        }

        @Test
        void age_defaultsTo18() {
            CreateWithDefaultsInput input = CreateWithDefaultsInput.builder().name("test").build();
            CreateWithDefaultsResponse res = client.mutations.createWithDefaults(input).block();
            assertEquals(18, res.getCreateWithDefaults().getAge());
        }

        @Test
        void isActive_defaultsToTrue() {
            CreateWithDefaultsInput input = CreateWithDefaultsInput.builder().name("test").build();
            CreateWithDefaultsResponse res = client.mutations.createWithDefaults(input).block();
            assertTrue(res.getCreateWithDefaults().getIsActive());
        }

        @Test
        void score_defaultsToFourPointFive() {
            CreateWithDefaultsInput input = CreateWithDefaultsInput.builder().name("test").build();
            CreateWithDefaultsResponse res = client.mutations.createWithDefaults(input).block();
            assertEquals(4.5, res.getCreateWithDefaults().getScore());
        }

        @Test
        void nickname_defaultsToAnonymous() {
            CreateWithDefaultsInput input = CreateWithDefaultsInput.builder().name("test").build();
            CreateWithDefaultsResponse res = client.mutations.createWithDefaults(input).block();
            assertEquals("anonymous", res.getCreateWithDefaults().getNickname());
        }

        @Test
        void tags_defaultsToDartAndGraphql() {
            CreateWithDefaultsInput input = CreateWithDefaultsInput.builder().name("test").build();
            CreateWithDefaultsResponse res = client.mutations.createWithDefaults(input).block();
            assertEquals(Arrays.asList("dart", "graphql"), res.getCreateWithDefaults().getTags());
        }

        @Test
        void name_isEchoed() {
            CreateWithDefaultsInput input = CreateWithDefaultsInput.builder().name("explicit-name").build();
            CreateWithDefaultsResponse res = client.mutations.createWithDefaults(input).block();
            assertEquals("explicit-name", res.getCreateWithDefaults().getName());
        }

        @Test
        void explicitValues_overrideDefaults() {
            CreateWithDefaultsInput input = CreateWithDefaultsInput.builder()
                    .name("override-test")
                    .role(Role.ADMIN)
                    .age(99)
                    .isActive(false)
                    .score(9.9)
                    .nickname("custom")
                    .tags(Arrays.asList("custom-tag"))
                    .build();
            CreateWithDefaultsResponse res = client.mutations.createWithDefaults(input).block();
            assertEquals("override-test", res.getCreateWithDefaults().getName());
            assertEquals(Role.ADMIN, res.getCreateWithDefaults().getRole());
            assertEquals(99, res.getCreateWithDefaults().getAge());
            assertFalse(res.getCreateWithDefaults().getIsActive());
            assertEquals(9.9, res.getCreateWithDefaults().getScore());
            assertEquals("custom", res.getCreateWithDefaults().getNickname());
            assertEquals(Arrays.asList("custom-tag"), res.getCreateWithDefaults().getTags());
        }
    }

    // ── createWithNestedDefaults — nested object/list defaults ───────────────

    @Nested
    class CreateWithNestedDefaults {

        @Test
        void name_isEchoed() {
            NestedDefaultsInput input = NestedDefaultsInput.builder().name("nested-test").build();
            CreateWithNestedDefaultsResponse res = client.mutations.createWithNestedDefaults(input).block();
            assertEquals("nested-test", res.getCreateWithNestedDefaults().getName());
        }

        // ── Object default ──────────────────────────────────────────────────

        @Test
        void address_defaultsToFullObject() {
            NestedDefaultsInput input = NestedDefaultsInput.builder().name("obj-default").build();
            CreateWithNestedDefaultsResponse res = client.mutations.createWithNestedDefaults(input).block();
            assertNotNull(res.getCreateWithNestedDefaults().getAddress());
            assertEquals("123 Main St", res.getCreateWithNestedDefaults().getAddress().getStreet());
            assertEquals("Springfield", res.getCreateWithNestedDefaults().getAddress().getCity());
            assertEquals("US", res.getCreateWithNestedDefaults().getAddress().getCountry());
            assertEquals("12345", res.getCreateWithNestedDefaults().getAddress().getZip());
        }

        // ── List-of-objects default ─────────────────────────────────────────

        @Test
        void contacts_defaultsToListOfTwo() {
            NestedDefaultsInput input = NestedDefaultsInput.builder().name("list-default").build();
            CreateWithNestedDefaultsResponse res = client.mutations.createWithNestedDefaults(input).block();
            assertNotNull(res.getCreateWithNestedDefaults().getContacts());
            assertEquals(2, res.getCreateWithNestedDefaults().getContacts().size());
            assertEquals("456 Oak Ave", res.getCreateWithNestedDefaults().getContacts().get(0).getStreet());
            assertEquals("Shelbyville", res.getCreateWithNestedDefaults().getContacts().get(0).getCity());
            assertNull(res.getCreateWithNestedDefaults().getContacts().get(0).getZip());
            assertEquals("789 Pine Rd", res.getCreateWithNestedDefaults().getContacts().get(1).getStreet());
            assertEquals("Capital City", res.getCreateWithNestedDefaults().getContacts().get(1).getCity());
            assertEquals("99999", res.getCreateWithNestedDefaults().getContacts().get(1).getZip());
        }

        // ── List-of-list-of-objects default ─────────────────────────────────

        @Test
        void matrix_defaultsToNestedList() {
            NestedDefaultsInput input = NestedDefaultsInput.builder().name("matrix-default").build();
            CreateWithNestedDefaultsResponse res = client.mutations.createWithNestedDefaults(input).block();
            assertNotNull(res.getCreateWithNestedDefaults().getMatrix());
            assertEquals(2, res.getCreateWithNestedDefaults().getMatrix().size());
            // Row 0: single address
            assertEquals(1, res.getCreateWithNestedDefaults().getMatrix().get(0).size());
            assertEquals("1st St", res.getCreateWithNestedDefaults().getMatrix().get(0).get(0).getStreet());
            assertEquals("Paris", res.getCreateWithNestedDefaults().getMatrix().get(0).get(0).getCity());
            assertEquals("FR", res.getCreateWithNestedDefaults().getMatrix().get(0).get(0).getCountry());
            assertEquals("75000", res.getCreateWithNestedDefaults().getMatrix().get(0).get(0).getZip());
            // Row 1: single address
            assertEquals(1, res.getCreateWithNestedDefaults().getMatrix().get(1).size());
            assertEquals("2nd St", res.getCreateWithNestedDefaults().getMatrix().get(1).get(0).getStreet());
            assertEquals("Lyon", res.getCreateWithNestedDefaults().getMatrix().get(1).get(0).getCity());
            assertEquals("FR", res.getCreateWithNestedDefaults().getMatrix().get(1).get(0).getCountry());
            assertEquals("69000", res.getCreateWithNestedDefaults().getMatrix().get(1).get(0).getZip());
        }

        // ── Explicit values override defaults ───────────────────────────────

        @Test
        void explicitValues_overrideNestedDefaults() {
            NestedDefaultsInput input = NestedDefaultsInput.builder()
                    .name("override-nested")
                    .address(new AddressInput("Custom St", "Custom City", "XX", null))
                    .contacts(Arrays.asList(new AddressInput("One", "Two", "Three", "44444")))
                    .matrix(Arrays.asList(
                            Arrays.asList(new AddressInput("A", "B", "C", null))))
                    .build();
            CreateWithNestedDefaultsResponse res = client.mutations.createWithNestedDefaults(input).block();
            assertNotNull(res.getCreateWithNestedDefaults().getAddress());
            assertEquals("Custom St", res.getCreateWithNestedDefaults().getAddress().getStreet());
            assertEquals("Custom City", res.getCreateWithNestedDefaults().getAddress().getCity());
            assertEquals("XX", res.getCreateWithNestedDefaults().getAddress().getCountry());
            assertNull(res.getCreateWithNestedDefaults().getAddress().getZip());

            assertEquals(1, res.getCreateWithNestedDefaults().getContacts().size());
            assertEquals("One", res.getCreateWithNestedDefaults().getContacts().get(0).getStreet());

            assertEquals(1, res.getCreateWithNestedDefaults().getMatrix().size());
            assertEquals("A", res.getCreateWithNestedDefaults().getMatrix().get(0).get(0).getStreet());
        }
    }
}
