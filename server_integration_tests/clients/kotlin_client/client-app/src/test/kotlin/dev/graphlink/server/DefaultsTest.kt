package dev.graphlink.server

import dev.graphlink.server.generated.client.GraphLinkClient
import dev.graphlink.server.generated.enums.Priority
import dev.graphlink.server.generated.inputs.ConfigInput
import kotlinx.coroutines.test.runTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DefaultsTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = Fixtures.newClient()
    }

    @Test
    fun inputFieldDefaultsAppliedWhenOmitted() = runTest {
        val c = client.queries.resolveConfig(ConfigInput()).resolveConfig
        assertEquals(25, c.pageSize)
        assertEquals(1.5, c.ratio)
        assertEquals("asc", c.sort)
        assertFalse(c.verbose!!)
        assertEquals(Priority.MEDIUM, c.priority)
        assertEquals(listOf("default", "seed"), c.tags)
        assertTrue(c.empties!!.isEmpty())
        assertNull(c.note)
    }

    @Test
    fun explicitValuesOverrideDefaults() = runTest {
        val c = client.queries.resolveConfig(
            ConfigInput(pageSize = 5, sort = "desc", priority = Priority.HIGH, note = "x"),
        ).resolveConfig
        assertEquals(5, c.pageSize)
        assertEquals("desc", c.sort)
        assertEquals(Priority.HIGH, c.priority)
        assertEquals("x", c.note)
    }

    @Test
    fun nestedObjectArgDefaultMergesWithFieldDefaults() = runTest {
        val range = client.queries.resolveRange().resolveRange
        assertEquals(5, range.min)
        assertEquals(100, range.max)
    }

    @Test
    fun argumentLevelScalarDefaults() = runTest {
        assertEquals("Hi world!", client.queries.greet().greet)
        assertEquals("Hi Bob!Hi Bob!", client.queries.greet(name = "Bob", times = 2).greet)
    }

    @Test
    fun enumArgumentPassedValueRoundTripsOmittedUsesDefaultHigh() = runTest {
        assertEquals(Priority.LOW, client.queries.echoPriority(Priority.LOW).echoPriority)
        assertEquals(Priority.HIGH, client.queries.echoPriority().echoPriority)
    }
}
