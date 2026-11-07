package dev.graphlink.test

import dev.graphlink.test.Fixtures.newRealClient
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.*
import dev.graphlink.test.generated.inputs.*
import dev.graphlink.test.generated.types.*
import kotlinx.coroutines.test.runTest
import kotlin.test.*

class ListShapesTest {

    private lateinit var client: GraphLinkClient
    private val known = Spelling.values().filter { it != Spelling.unknownValue__ }

    @BeforeTest
    fun setUp() {
        client = newRealClient()
    }

    private suspend fun shapes(mode: String) = client.queries.listShapes(mode).listShapes

    @Test
    fun scalarsWithNulls() = runTest {
        val s = shapes("full")
        assertEquals(listOf(1, 2, 3), s.a)
        assertEquals(listOf(1, 2, 3), s.b)
        assertEquals(listOf(1, null, 3), s.c)
        assertEquals(listOf<Int?>(null), s.d)
    }

    @Test
    fun nestedLists() = runTest {
        val s = shapes("full")
        assertEquals(listOf(listOf(1, 2), listOf(3)), s.e)
        assertEquals(listOf(listOf(1, null), null), s.f)
    }

    @Test
    fun enumsWithNulls() = runTest {
        assertEquals(listOf(Spelling.A, null, Spelling.B2), shapes("full").g)
    }

    @Test
    fun objectsUnionsAndInterfaces() = runTest {
        val s = shapes("full")
        assertEquals(listOf(640, null), s.h.map { it?.width })
        assertEquals(listOf("Photo", null, "Video"), s.i.map { it?.let { v -> v::class.simpleName } })
        assertEquals(listOf("Comment", null), s.j.map { it?.let { v -> v::class.simpleName } })
    }

    @Test
    fun emptyListsStayEmpty() = runTest {
        val s = shapes("empty")
        assertEquals(listOf(emptyList(), emptyList(), emptyList(), emptyList()), listOf(s.b, s.d, s.f, s.e))
    }

    @Test
    fun nullListsStayNullWhileRequiredOnesAreEmpty() = runTest {
        val s = shapes("null")
        assertNull(s.b)
        assertNull(s.d)
        assertNull(s.f)
        assertTrue(s.a.isEmpty() && s.g.isEmpty() && s.i.isEmpty())
    }

    @Test
    fun listArgumentsRoundTrip() = runTest {
        val r = client.queries.echoArgs(
            a = listOf(1, 2), b = listOf(1, null), c = listOf(listOf(1), listOf(), listOf(2, 3)),
            e = listOf(Spelling.X_Y, Spelling.HTTP2_OK), f = listOf(null, Spelling.V1),
        ).echoArgs
        assertEquals(listOf(1, 2), r.a)
        assertEquals(listOf(1, null), r.b)
        assertEquals(listOf(listOf(1), listOf(), listOf(2, 3)), r.c)
        assertEquals(listOf(Spelling.X_Y, Spelling.HTTP2_OK), r.e)
        assertEquals(listOf(null, Spelling.V1), r.f)
    }

    @Test
    fun omittedListsAreNullAndDefaultsApply() = runTest {
        val r = client.queries.echoArgs(a = listOf(), e = listOf()).echoArgs
        assertNull(r.b)
        assertNull(r.c)
        assertNull(r.f)
        assertEquals(listOf(Spelling.A, Spelling.B2), r.g)
        assertEquals(OnlyOne.ONLY, r.one)
    }

    @Test
    fun explicitlyEmptyDefaultBearingListIsKept() = runTest {
        assertEquals(listOf(), client.queries.echoArgs(a = listOf(), e = listOf(), g = listOf()).echoArgs.g)
    }

    @Test
    fun explicitNullOverridesTheDefault() = runTest {
        assertNull(client.queries.echoArgs(a = listOf(), e = listOf(), g = null).echoArgs.g)
    }

    @Test
    fun listInputFieldsRoundTrip() = runTest {
        val r = client.queries.echoInput(
            ListsInput(
                a = listOf(3, 4), b = listOf(null, 5), c = listOf(listOf(1, 2), listOf()),
                e = listOf(Spelling.SNAKE_CASE_2), f = listOf(Spelling.A, null), g = listOf(Spelling.V1),
            )
        ).echoInput
        assertEquals(listOf(3, 4), r.a)
        assertEquals(listOf(null, 5), r.b)
        assertEquals(listOf(listOf(1, 2), listOf()), r.c)
        assertEquals(listOf(Spelling.SNAKE_CASE_2), r.e)
        assertEquals(listOf(Spelling.A, null), r.f)
        assertEquals(listOf(Spelling.V1), r.g)
    }

    @Test
    fun inputDefaultsReachTheServer() = runTest {
        val r = client.queries.echoInput(ListsInput(a = listOf(), e = listOf())).echoInput
        assertEquals(listOf(Spelling.A, Spelling.B2), r.g)
        assertEquals(OnlyOne.ONLY, r.one)
    }

    @Test
    fun largeListOfScalars() = runTest {
        val r = client.queries.bigInts(50000).bigInts
        assertEquals(50000, r.size)
        assertEquals(49999, r.last())
    }

    @Test
    fun largeListOfObjects() = runTest {
        val r = client.queries.bigPhotos(20000).bigPhotos
        assertEquals(20000, r.size)
        assertEquals("p19999", r.last().id)
        assertEquals(19999, r.last().width)
    }

    @Test
    fun everySpellingRoundTrips() = runTest {
        assertEquals(known, client.queries.echoArgs(a = listOf(), e = known).echoArgs.e)
    }

    @Test
    fun wireNamesAreTheDeclaredOnes() {
        assertEquals(listOf("A", "B2", "x__y", "http2_ok", "v1", "snake_case_2"), known.map { it.toJson() })
    }

    @Test
    fun enumUsedOnlyAsArgument() = runTest {
        assertEquals("P2", client.queries.argOnly(ArgOnly.P2).argOnly)
    }

    @Test
    fun enumUsedOnlyInResponse() = runTest {
        assertEquals(RespOnly.R2, client.queries.respOnly().respOnly)
    }

    @Test
    fun unknownEnumValueInAField() = runTest {
        val p = client.queries.phaseProbe().phaseProbe
        assertEquals(Phase.unknownValue__, p.single)
        assertEquals(Phase.unknownValue__, p.maybe)
    }

    @Test
    fun unknownEnumValueInListElements() = runTest {
        val p = client.queries.phaseProbe().phaseProbe
        assertEquals(listOf(Phase.OPEN, Phase.unknownValue__, Phase.CLOSED), p.list)
        assertEquals(listOf(Phase.unknownValue__, null), p.nullableList)
    }

    @Test
    fun unknownEnumValueInAUnionMember() = runTest {
        assertEquals(Phase.unknownValue__, assertIs<Phased>(client.queries.phaseHolder().phaseHolder).phase)
    }
}
