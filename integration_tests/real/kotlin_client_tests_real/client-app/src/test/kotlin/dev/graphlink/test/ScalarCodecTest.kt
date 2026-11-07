package dev.graphlink.test

import dev.graphlink.test.Fixtures.newRealClient
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.inputs.ScalarsInput
import kotlinx.coroutines.test.runTest
import kotlin.test.*

class ScalarCodecTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = newRealClient()
    }

    @Test
    fun codecScalarIsDecodedInAResponse() = runTest {
        assertEquals("opaque:o-1", client.queries.scalarFixture().scalarFixture.opaque)
    }

    @Test
    fun codecScalarIsEncodedInAnInputFieldAndDecodedAgain() = runTest {
        val input = ScalarsInput(dt = "x", long = 1, dts = listOf(), opaque = "opaque:xyz")
        assertEquals("opaque:xyz", client.queries.echoScalars(input).echoScalars.opaque)
    }

    @Test
    fun codecScalarIsEncodedInAnOperationArgumentAndDecodedAgain() = runTest {
        assertEquals("opaque:abc", client.queries.echoScalarArgs(dt = "x", dts = listOf(), opaque = "opaque:abc").echoScalarArgs.opaque)
    }

    @Test
    fun codecScalarKeepsNullAsNull() = runTest {
        assertNull(client.queries.echoScalarArgs(dt = "x", dts = listOf()).echoScalarArgs.opaque)
        assertNull(client.queries.echoScalars(ScalarsInput(dt = "x", long = 1, dts = listOf())).echoScalars.opaque)
    }

    @Test
    fun aliasScalarsKeepLongPrecisionAndJsonShape() = runTest {
        val bag = client.queries.scalarFixture().scalarFixture
        assertEquals(9007199254740993L, bag.long)
        assertEquals(listOf(1L, null, 9223372036854775807L), bag.longs)
        assertEquals("2026-01-02T03:04:05Z", bag.dt)
        assertEquals("x", (bag.json as Map<*, *>)["name"])
    }

    @Test
    fun longDefaultReachesTheServer() = runTest {
        assertEquals(9007199254740993L, client.queries.echoScalarArgs(dt = "x", dts = listOf()).echoScalarArgs.long)
    }
}
