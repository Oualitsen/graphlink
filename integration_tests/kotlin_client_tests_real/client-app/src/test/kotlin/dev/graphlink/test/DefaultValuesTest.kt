package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.Role
import dev.graphlink.test.generated.inputs.AddressInput
import dev.graphlink.test.generated.inputs.CreateWithDefaultsInput
import dev.graphlink.test.generated.inputs.NestedDefaultsInput
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import kotlin.test.*
import dev.graphlink.test.Fixtures.newRealClient

class DefaultValuesTest {

    private lateinit var client: GraphLinkClient

    @BeforeEach
    fun setUp() {
        client = newRealClient()
    }

    // ── listUsersWithDefaults — operation argument defaults ──────────────────

    @Nested
    inner class ListUsersWithDefaults {

        @Test
        fun returnsUsers_withoutArguments() = runTest {
            val res = client.queries.listUsersWithDefaults()
            assertNotNull(res.listUsersWithDefaults)
            assertTrue(res.listUsersWithDefaults.isNotEmpty())
        }

        @Test
        fun explicitLimit_overridesDefault() = runTest {
            val res = client.queries.listUsersWithDefaults(limit = 1)
            assertEquals(1, res.listUsersWithDefaults.size)
        }

        @Test
        fun explicitRole_canBeProvided() = runTest {
            val res = client.queries.listUsersWithDefaults(role = Role.ADMIN)
            assertTrue(res.listUsersWithDefaults.isNotEmpty())
        }
    }

    // ── createWithDefaults — input field defaults ────────────────────────────

    @Nested
    inner class CreateWithDefaults {

        @Test
        fun role_defaultsToUSER() = runTest {
            val input = CreateWithDefaultsInput(name = "test")
            val res = client.mutations.createWithDefaults(input)
            assertEquals(Role.USER, res.createWithDefaults.role)
        }

        @Test
        fun age_defaultsTo18() = runTest {
            val input = CreateWithDefaultsInput(name = "test")
            val res = client.mutations.createWithDefaults(input)
            assertEquals(18, res.createWithDefaults.age)
        }

        @Test
        fun isActive_defaultsToTrue() = runTest {
            val input = CreateWithDefaultsInput(name = "test")
            val res = client.mutations.createWithDefaults(input)
            assertTrue(res.createWithDefaults.isActive)
        }

        @Test
        fun score_defaultsToFourPointFive() = runTest {
            val input = CreateWithDefaultsInput(name = "test")
            val res = client.mutations.createWithDefaults(input)
            assertEquals(4.5, res.createWithDefaults.score)
        }

        @Test
        fun nickname_defaultsToAnonymous() = runTest {
            val input = CreateWithDefaultsInput(name = "test")
            val res = client.mutations.createWithDefaults(input)
            assertEquals("anonymous", res.createWithDefaults.nickname)
        }

        @Test
        fun tags_defaultsToDartAndGraphql() = runTest {
            val input = CreateWithDefaultsInput(name = "test")
            val res = client.mutations.createWithDefaults(input)
            assertEquals(listOf("dart", "graphql"), res.createWithDefaults.tags)
        }

        @Test
        fun name_isEchoed() = runTest {
            val input = CreateWithDefaultsInput(name = "explicit-name")
            val res = client.mutations.createWithDefaults(input)
            assertEquals("explicit-name", res.createWithDefaults.name)
        }

        @Test
        fun explicitValues_overrideDefaults() = runTest {
            val input = CreateWithDefaultsInput(
                name = "override-test",
                role = Role.ADMIN,
                age = 99,
                isActive = false,
                score = 9.9,
                nickname = "custom",
                tags = listOf("custom-tag"),
            )
            val res = client.mutations.createWithDefaults(input)
            assertEquals("override-test", res.createWithDefaults.name)
            assertEquals(Role.ADMIN, res.createWithDefaults.role)
            assertEquals(99, res.createWithDefaults.age)
            assertFalse(res.createWithDefaults.isActive)
            assertEquals(9.9, res.createWithDefaults.score)
            assertEquals("custom", res.createWithDefaults.nickname)
            assertEquals(listOf("custom-tag"), res.createWithDefaults.tags)
        }
    }

    // ── createWithNestedDefaults — nested object/list defaults ───────────────

    @Nested
    inner class CreateWithNestedDefaults {

        @Test
        fun name_isEchoed() = runTest {
            val input = NestedDefaultsInput(name = "nested-test")
            val res = client.mutations.createWithNestedDefaults(input)
            assertEquals("nested-test", res.createWithNestedDefaults.name)
        }

        // ── Object default ──────────────────────────────────────────────────

        @Test
        fun address_defaultsToFullObject() = runTest {
            val input = NestedDefaultsInput(name = "obj-default")
            val res = client.mutations.createWithNestedDefaults(input)
            assertNotNull(res.createWithNestedDefaults.address)
            assertEquals("123 Main St", res.createWithNestedDefaults.address!!.street)
            assertEquals("Springfield", res.createWithNestedDefaults.address!!.city)
            assertEquals("US", res.createWithNestedDefaults.address!!.country)
            assertEquals("12345", res.createWithNestedDefaults.address!!.zip)
        }

        // ── List-of-objects default ─────────────────────────────────────────

        @Test
        fun contacts_defaultsToListOfTwo() = runTest {
            val input = NestedDefaultsInput(name = "list-default")
            val res = client.mutations.createWithNestedDefaults(input)
            assertNotNull(res.createWithNestedDefaults.contacts)
            assertEquals(2, res.createWithNestedDefaults.contacts!!.size)
            assertEquals("456 Oak Ave", res.createWithNestedDefaults.contacts!![0]!!.street)
            assertEquals("Shelbyville", res.createWithNestedDefaults.contacts!![0]!!.city)
            assertNull(res.createWithNestedDefaults.contacts!![0]!!.zip)
            assertEquals("789 Pine Rd", res.createWithNestedDefaults.contacts!![1]!!.street)
            assertEquals("Capital City", res.createWithNestedDefaults.contacts!![1]!!.city)
            assertEquals("99999", res.createWithNestedDefaults.contacts!![1]!!.zip)
        }

        // ── List-of-list-of-objects default ─────────────────────────────────

        @Test
        fun matrix_defaultsToNestedList() = runTest {
            val input = NestedDefaultsInput(name = "matrix-default")
            val res = client.mutations.createWithNestedDefaults(input)
            assertNotNull(res.createWithNestedDefaults.matrix)
            assertEquals(2, res.createWithNestedDefaults.matrix!!.size)
            // Row 0: single address
            assertEquals(1, res.createWithNestedDefaults.matrix!![0]!!.size)
            assertEquals("1st St", res.createWithNestedDefaults.matrix!![0]!![0]!!.street)
            assertEquals("Paris", res.createWithNestedDefaults.matrix!![0]!![0]!!.city)
            assertEquals("FR", res.createWithNestedDefaults.matrix!![0]!![0]!!.country)
            assertEquals("75000", res.createWithNestedDefaults.matrix!![0]!![0]!!.zip)
            // Row 1: single address
            assertEquals(1, res.createWithNestedDefaults.matrix!![1]!!.size)
            assertEquals("2nd St", res.createWithNestedDefaults.matrix!![1]!![0]!!.street)
            assertEquals("Lyon", res.createWithNestedDefaults.matrix!![1]!![0]!!.city)
            assertEquals("FR", res.createWithNestedDefaults.matrix!![1]!![0]!!.country)
            assertEquals("69000", res.createWithNestedDefaults.matrix!![1]!![0]!!.zip)
        }

        // ── Explicit values override defaults ───────────────────────────────

        @Test
        fun explicitValues_overrideNestedDefaults() = runTest {
            val input = NestedDefaultsInput(
                name = "override-nested",
                address = AddressInput("Custom St", "Custom City", "XX", null),
                contacts = listOf(AddressInput("One", "Two", "Three", "44444")),
                matrix = listOf(listOf(AddressInput("A", "B", "C", null))),
            )
            val res = client.mutations.createWithNestedDefaults(input)
            assertNotNull(res.createWithNestedDefaults.address)
            assertEquals("Custom St", res.createWithNestedDefaults.address!!.street)
            assertEquals("Custom City", res.createWithNestedDefaults.address!!.city)
            assertEquals("XX", res.createWithNestedDefaults.address!!.country)
            assertNull(res.createWithNestedDefaults.address!!.zip)

            assertEquals(1, res.createWithNestedDefaults.contacts!!.size)
            assertEquals("One", res.createWithNestedDefaults.contacts!![0]!!.street)

            assertEquals(1, res.createWithNestedDefaults.matrix!!.size)
            assertEquals("A", res.createWithNestedDefaults.matrix!![0]!![0]!!.street)
        }
    }
}
