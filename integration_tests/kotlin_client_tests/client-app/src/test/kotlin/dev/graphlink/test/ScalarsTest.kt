package dev.graphlink.test

import dev.graphlink.test.generated.client.GraphLinkClient
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.kAllScalarsNullJson
import dev.graphlink.test.Fixtures.kAllScalarsPresentJson
import dev.graphlink.test.Fixtures.newClient

class ScalarsTest {

    private lateinit var adapter: MockAdapter
    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        adapter = MockAdapter()
        client = newClient(adapter, MockWebSocketAdapter())
    }

    // ── Non-nullable scalar fields ────────────────────────────────────────────

    @Nested
    inner class NonNullableScalarFields {

        @BeforeTest
        fun register() {
            adapter.registerData("getAllScalars", mapOf("getAllScalars" to kAllScalarsNullJson))
        }

        @Test
        fun id_deserializesToString() = runTest {
            val s = client.queries.getAllScalars("scalar-1").getAllScalars
            assertIs<String>(s.id)
            assertEquals("scalar-1", s.id)
        }

        @Test
        fun strVal_deserializesToString() = runTest {
            val s = client.queries.getAllScalars("scalar-1").getAllScalars
            assertIs<String>(s.strVal)
            assertEquals("hello world", s.strVal)
        }

        @Test
        fun intVal_deserializesToInt() = runTest {
            val s = client.queries.getAllScalars("scalar-1").getAllScalars
            assertIs<Int>(s.intVal)
            assertEquals(42, s.intVal)
        }

        @Test
        fun floatVal_deserializesToDouble() = runTest {
            val s = client.queries.getAllScalars("scalar-1").getAllScalars
            assertIs<Double>(s.floatVal)
            assertEquals(3.14, s.floatVal, 0.001)
        }

        @Test
        fun boolVal_deserializesToBoolean() = runTest {
            val s = client.queries.getAllScalars("scalar-1").getAllScalars
            assertIs<Boolean>(s.boolVal)
            assertTrue(s.boolVal)
        }
    }

    // ── Nullable scalar fields — null in response ─────────────────────────────

    @Nested
    inner class NullableScalarFields_Null {

        @BeforeTest
        fun register() {
            adapter.registerData("getAllScalars", mapOf("getAllScalars" to kAllScalarsNullJson))
        }

        @Test
        fun nullableStr_isNull() = runTest {
            assertNull(client.queries.getAllScalars("scalar-1").getAllScalars.nullableStr)
        }

        @Test
        fun nullableInt_isNull() = runTest {
            assertNull(client.queries.getAllScalars("scalar-1").getAllScalars.nullableInt)
        }

        @Test
        fun nullableFloat_isNull() = runTest {
            assertNull(client.queries.getAllScalars("scalar-1").getAllScalars.nullableFloat)
        }

        @Test
        fun nullableBool_isNull() = runTest {
            assertNull(client.queries.getAllScalars("scalar-1").getAllScalars.nullableBool)
        }

        @Test
        fun nullableId_isNull() = runTest {
            assertNull(client.queries.getAllScalars("scalar-1").getAllScalars.nullableId)
        }
    }

    // ── Nullable scalar fields — values present ───────────────────────────────

    @Nested
    inner class NullableScalarFields_Present {

        @BeforeTest
        fun register() {
            adapter.registerData("getAllScalars", mapOf("getAllScalars" to kAllScalarsPresentJson))
        }

        @Test
        fun nullableStr_hasValue() = runTest {
            assertEquals("present", client.queries.getAllScalars("scalar-2").getAllScalars.nullableStr)
        }

        @Test
        fun nullableInt_hasValue() = runTest {
            assertEquals(99, client.queries.getAllScalars("scalar-2").getAllScalars.nullableInt)
        }

        @Test
        fun nullableFloat_hasValue() = runTest {
            assertEquals(2.718, client.queries.getAllScalars("scalar-2").getAllScalars.nullableFloat!!, 0.001)
        }

        @Test
        fun nullableBool_isFalse_notNull() = runTest {
            val v = client.queries.getAllScalars("scalar-2").getAllScalars.nullableBool
            assertNotNull(v)
            assertFalse(v)
        }

        @Test
        fun negativeInt_deserializesCorrectly() = runTest {
            assertEquals(-1, client.queries.getAllScalars("scalar-2").getAllScalars.intVal)
        }

        @Test
        fun negativeFloat_deserializesCorrectly() = runTest {
            assertEquals(-0.5, client.queries.getAllScalars("scalar-2").getAllScalars.floatVal, 0.001)
        }

        @Test
        fun boolFalse_isNotTreatedAsNull() = runTest {
            val v = client.queries.getAllScalars("scalar-2").getAllScalars.boolVal
            assertNotNull(v)
            assertFalse(v)
        }
    }

    // ── Outgoing request shape ────────────────────────────────────────────────

    @Nested
    inner class OutgoingRequestShape {

        @BeforeTest
        fun register() {
            adapter.registerData("getAllScalars", mapOf("getAllScalars" to kAllScalarsNullJson))
        }

        @Test
        fun idArgument_isSentAsStringInVariables() = runTest {
            client.queries.getAllScalars("scalar-1")
            assertEquals("scalar-1", adapter.getLastCall()?.variables?.get("id"))
        }

        @Test
        fun operationName_isGetAllScalars() = runTest {
            client.queries.getAllScalars("scalar-1")
            assertEquals("getAllScalars", adapter.getLastCall()?.operationName)
        }
    }
}
