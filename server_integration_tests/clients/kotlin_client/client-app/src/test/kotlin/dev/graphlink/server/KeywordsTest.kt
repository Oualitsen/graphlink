package dev.graphlink.server

import dev.graphlink.server.generated.client.GraphLinkClient
import dev.graphlink.server.generated.enums.Keyword
import dev.graphlink.server.generated.inputs.ReservedInput
import kotlinx.coroutines.test.runTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class KeywordsTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = Fixtures.newClient()
    }

    @Test
    fun reservedWordFieldsRoundTripBothDartOnlyJavaOnly() = runTest {
        val r = client.queries.reserved().reserved
        assertEquals("cls", r.class_)
        assertEquals(42, r.return_)
        assertTrue(r.new)
        assertEquals("def", r.default)
        assertEquals("yes", r.is_)
        assertEquals("inside", r.in_)
        assertEquals("w", r.with)
        assertEquals(7, r.int)
        assertFalse(r.synchronized)
        assertEquals("n", r.native)
        assertEquals(Keyword.CLASS, r.kind)
        assertEquals("v", r.nested.value)
        assertEquals("tok", r.secret.token)
    }

    @Test
    fun reservedOperationNamePlusReservedArgumentNames() = runTest {
        val res = client.queries.switch(class_ = "x", return_ = 5)
        assertEquals("x", res.switch.class_)
        assertEquals(5, res.switch.return_)
    }

    @Test
    fun leadingUnderscoreOperation() = runTest {
        val res = client.queries.status()
        assertEquals("ok", res.status)
    }

    @Test
    fun collidingFieldNamesStayDistinct() = runTest {
        val c = client.queries.collide().collide
        assertTrue(listOf(c.class_2, c.class2).containsAll(listOf("A", "B")))
    }

    @Test
    fun reservedWordInputFieldsMutation() = runTest {
        val res = client.mutations.echoReserved(
            ReservedInput(class_ = "X", return_ = 5, default = "D", is_ = true, synchronized = 3),
        )
        assertEquals("X", res.echoReserved.class_)
        assertEquals(5, res.echoReserved.return_)
        assertEquals("D", res.echoReserved.default)
    }
}
