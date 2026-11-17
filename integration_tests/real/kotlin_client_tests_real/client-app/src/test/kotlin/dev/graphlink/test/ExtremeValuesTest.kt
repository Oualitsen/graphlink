package dev.graphlink.test

import dev.graphlink.test.Fixtures.newRealClient
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.inputs.*
import kotlinx.coroutines.test.runTest
import kotlin.test.*

class ExtremeValuesTest {
    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = newRealClient()
    }

    @Test
    fun intAtBoth32BitLimits() = runTest {
        val r = client.queries.echoEverything(EverythingInput(i = 2147483647, neg = -2147483648)).echoEverything
        assertEquals(2147483647, r.i)
        assertEquals(-2147483648, r.neg)
    }

    @Test
    fun floatAt1e308AndNegativeZero() = runTest {
        val r = client.queries.echoEverything(EverythingInput(f = 1e308, exp = -0.0)).echoEverything
        assertEquals(1e308, r.f)
        assertEquals(-0.0, r.exp)
    }

    @Test
    fun aStringWithANulCharacter() = runTest {
        assertEquals("a\u0000b", client.queries.echoEverything(EverythingInput(s = "a\u0000b")).echoEverything.s)
    }

    @Test
    fun aStringWithLoneSurrogates() = runTest {
        val sent = "x\ud800y\udc00z"
        val received = client.queries.echoEverything(EverythingInput(s = sent)).echoEverything.s
        assertEquals("x?y?z", received, "the JVM's UTF-8 encoder replaces a lone surrogate with '?'")
    }
}
