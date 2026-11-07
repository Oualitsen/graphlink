package dev.graphlink.test

import dev.graphlink.test.Fixtures.newRealClient
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.*
import dev.graphlink.test.generated.inputs.*
import dev.graphlink.test.generated.types.*
import kotlinx.coroutines.test.runTest
import kotlin.test.*

class LiteralsTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = newRealClient()
    }

    private fun assertNasty(r: NastyEcho) {
        assertEquals("cost \$5 and \${x} and \$\$", r.dollar)
        assertEquals("say \"hi\" it's", r.quote)
        assertEquals("C:\\dir\\file\\n", r.backslash)
        assertEquals("line1\nline2\ttab", r.newline)
        assertEquals("100% {braces} {{x}} %s %d", r.percent)
        assertEquals("a */ b // c /* d", r.comments)
        assertEquals("\"\"\" ''' ```", r.triple)
        assertEquals("café 中 😀", r.unicode)
        assertEquals("é中😀", r.nonAscii)
    }

    @Test
    fun stringDefaultsOnOperationArguments() = runTest {
        assertNasty(client.queries.echoNastyArgs().echoNastyArgs)
    }

    @Test
    fun stringDefaultsOnInputFieldsThroughAnInputDefaultingToEmptyObject() = runTest {
        assertNasty(client.queries.echoNasty().echoNasty)
    }

    @Test
    fun anExplicitValueReplacesTheDefault() = runTest {
        val r = client.queries.echoNastyArgs(dollar = "\$y").echoNastyArgs
        assertEquals("\$y", r.dollar)
        assertEquals("say \"hi\" it's", r.quote)
    }

    @Test
    fun stringLiteralsWrittenInlineInAnOperation() = runTest {
        val r = client.queries.nastyLiteral().echoNastyArgs
        assertEquals("cost \$5 \${x}", r.dollar)
        assertEquals("say \"hi\"", r.quote)
        assertEquals("C:\\dir", r.backslash)
        assertEquals("a\nb", r.newline)
        assertEquals("é😀", r.unicode)
        assertEquals("block \"x\" ", r.triple)
    }

    @Test
    fun defaultsOfEveryKind() = runTest {
        val r = client.queries.echoEverything(EverythingInput()).echoEverything
        assertEquals(listOf(42, -7, 2147483647), listOf(r.i, r.neg, r.big))
        assertEquals(listOf(3.14, 1000.0), listOf(r.f, r.exp))
        assertEquals(listOf(true, false), listOf(r.b, r.bf))
        assertEquals(listOf("x", "abc"), listOf(r.s, r.id))
        assertEquals(Spelling.X_Y, r.e)
        assertEquals(listOf(1, 2, 3), r.ints)
        assertEquals(listOf(listOf(1), listOf(2, 3)), r.nested)
        assertEquals(5, r.inner!!.n)
        assertEquals("inner", r.inner!!.label)
        assertNull(r.nothing)
        assertEquals(listOf(), r.emptyList)
        assertEquals("dflt", r.emptyObj!!.label)
        assertEquals(1, r.emptyObj!!.n)
    }

    @Test
    fun anArgumentWhoseInputTypeHasItsOwnDefaults() = runTest {
        val r = client.queries.echoInner().echoInner
        assertEquals(9, r.n)
        assertEquals("dflt", r.label)
        assertEquals(listOf("a"), r.tags)
    }

    @Test
    fun recursiveTree() = runTest {
        val tree = Tree(1, listOf(Tree(2, listOf(Tree(4))), Tree(3)))
        val r = client.queries.treeStats(tree).treeStats
        assertEquals(listOf(1, 2, 4, 3), r.flat)
        assertEquals(3, r.depth)
    }

    @Test
    fun mutuallyRecursiveInputs() = runTest {
        assertEquals(3, client.queries.pingLength(Ping(1, Pong(2, Ping(3)))).pingLength)
    }

    @Test
    fun oneOfInput() = runTest {
        assertEquals("cat:Tom", client.queries.describePet(Pet(cat = "Tom")).describePet)
        assertEquals("dog:3", client.queries.describePet(Pet(dog = 3)).describePet)
    }

    @Test
    @Suppress("DEPRECATION")
    fun deprecatedFieldsArgumentsAndEnumValuesStillWork() = runTest {
        val r = client.queries.legacy(withReason = "a", plain = "b").legacy
        assertEquals("a", r.old)
        assertEquals("b", r.older)
        assertEquals(Mood.CALM, r.mood)
    }
}
