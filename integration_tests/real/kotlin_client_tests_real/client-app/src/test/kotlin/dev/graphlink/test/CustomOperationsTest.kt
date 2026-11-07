package dev.graphlink.test

import dev.graphlink.test.Fixtures.newRealClient
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.*
import dev.graphlink.test.generated.inputs.*
import kotlinx.coroutines.test.runTest
import kotlin.test.*

class CustomOperationsTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = newRealClient()
    }

    @Test
    fun aFragmentThatSpreadsAnotherFragment() = runTest {
        val u = client.queries.fragNested("user-1").getUser
        assertEquals(listOf("user-1", "Alice Smith"), listOf(u.id, u.name))
        assertEquals(UserStatus.ACTIVE, u.status)
    }

    @Test
    fun oneFragmentReusedByTwoOperations() = runTest {
        val ids = client.queries.fragReuseA().listUsers.map { it.id }
        assertTrue(ids.containsAll(listOf("user-1", "user-2")))
        val one = client.queries.fragReuseB("user-2").getUser
        assertEquals(listOf("user-2", "Bob Jones"), listOf(one.id, one.name))
        assertNotNull(one.email)
    }

    @Test
    fun aFragmentOnAnInterfaceNextToAnInlineFragment() = runTest {
        val feed = client.queries.fragOnInterface().feed
        assertTrue(feed.isNotEmpty())
        assertTrue(feed.all { it.id.isNotEmpty() && it.createdBy.isNotEmpty() })
    }

    @Test
    fun severalRootFieldsSharingOneFragment() = runTest {
        val r = client.queries.multiRoot()
        assertEquals("Alice Smith", r.first.name)
        assertEquals("Bob Jones", r.second.name)
        assertTrue(r.all.map { it.id }.containsAll(listOf("user-1", "user-2")))
    }

    @Test
    fun variableDefaultsApplyWhenNotGiven() = runTest {
        assertEquals(1, client.queries.varsDefaults().searchUsers.size)
    }

    @Test
    fun anExplicitValueReplacesTheVariableDefault() = runTest {
        assertEquals(listOf("user-1"), client.queries.varsDefaults(name = "Alice", limit = 5).searchUsers.map { it.id })
    }

    @Test
    fun listNestedListAndEnumVariables() = runTest {
        val r = client.queries.varsLists(
            a = listOf(1, 2), b = listOf(1, null), c = listOf(listOf(1), listOf(2, 3)),
            e = listOf(Spelling.X_Y), f = listOf(null, Spelling.V1),
        ).echoArgs
        assertEquals(listOf(1, 2), r.a)
        assertEquals(listOf(1, null), r.b)
        assertEquals(listOf(listOf(1), listOf(2, 3)), r.c)
        assertEquals(listOf(Spelling.X_Y), r.e)
        assertEquals(listOf(null, Spelling.V1), r.f)
    }

    @Test
    fun aNullableEnumVariable() = runTest {
        assertEquals(OnlyOne.ONLY, client.queries.varsEnum(OnlyOne.ONLY).echoArgs.one)
    }

    @Test
    fun anInputObjectVariable() = runTest {
        val r = client.queries.varsInput(InnerInput(n = 4, label = "x")).echoInner
        assertEquals(listOf<Any?>(4, "x"), listOf(r.n, r.label))
    }

    @Test
    fun nullableVersusNonNullVariables() = runTest {
        val given = client.queries.varsNullable(dollar = "\$d", quote = "q").echoNastyArgs
        assertEquals(listOf<String?>("\$d", "q"), listOf(given.dollar, given.quote))
        val left = client.queries.varsNullable(quote = "q").echoNastyArgs
        assertEquals(listOf<String?>(null, "q"), listOf(left.dollar, left.quote))
    }

    @Test
    fun includeAndSkipWithVariables() = runTest {
        val both = client.queries.conditionalVars(withEmail = true, skipName = false).getUser
        assertEquals(listOf<String?>("user-1", "Alice Smith", "alice@test.com"), listOf(both.id, both.name, both.email))
        val neither = client.queries.conditionalVars(withEmail = false, skipName = true).getUser
        assertEquals(listOf<String?>("user-1", null, null), listOf(neither.id, neither.name, neither.email))
    }

    @Test
    fun includeAndSkipWithLiterals() = runTest {
        val u = client.queries.conditionalLiterals().getUser
        assertEquals("Alice Smith", u.name)
        assertNull(u.email)
        assertEquals(UserStatus.ACTIVE, u.status)
        assertNull(u.priority)
    }

    @Test
    fun aliases() = runTest {
        val r = client.queries.aliasesSameField()
        assertEquals(listOf("user-1", "user-2"), listOf(r.a.id, r.b.id))
        val k = client.queries.aliasKeywords().class_
        assertEquals(listOf("Alice Smith", "user-1"), listOf(k.default, k.import))
        assertEquals("alice@test.com", client.queries.aliasEqualsOtherField().getUser.name)
    }

    @Test
    fun operationNamesThatCollide() = runTest {
        assertEquals("user-1", client.queries.user().getUser.id)
        assertEquals("ph1", client.queries.photo2().photo!!.id)
        assertTrue(client.queries.return_().listUsers.isNotEmpty())
        assertEquals("s1", client.queries.shelf().shelf.id)
        assertEquals("user-1", client.queries.getUserResponse().getUser.id)
    }

    @Test
    fun fieldArgumentsOfEveryShape() = runTest {
        assertEquals(
            listOf("tags=[a, b]", "kind=x__y", "filter={n=3, label=L}", "limit=5"),
            client.queries.shelfItems().shelf.items,
        )
        val r = client.queries.shelfItemsVars(
            tags = listOf("t"), kind = Spelling.V1, filter = InnerInput(n = 1, label = "f"), limit = 7,
        ).shelf.items
        assertEquals(listOf("tags=[t]", "kind=v1", "limit=7"), listOf(r[0], r[1], r[3]))
        assertEquals("limit=2", client.queries.shelfItemsDefaults().shelf.items.last())
    }

    @Test
    fun literalArgumentsOfEveryKind() = runTest {
        val l = client.queries.literalLists().echoArgs
        assertEquals(listOf(1, 2, 3), l.a)
        assertEquals(listOf(1, null), l.b)
        assertEquals(listOf(listOf(1), listOf(2, 3)), l.c)
        assertEquals(listOf(Spelling.A, Spelling.X_Y), l.e)
        assertEquals(listOf(null, Spelling.V1), l.f)
        assertEquals(listOf(Spelling.SNAKE_CASE_2), l.g)
        assertEquals(OnlyOne.ONLY, l.one)

        val i = client.queries.literalInput().echoInput
        assertEquals(listOf(4), i.a)
        assertEquals(listOf(null, 5), i.b)
        assertEquals(listOf(listOf(6)), i.c)

        val s = client.queries.literalScalars().echoEverything
        assertEquals(listOf<Any?>(5, -3, 9), listOf(s.i, s.neg, s.big))
        assertEquals(listOf(2.5, 100.0), listOf(s.f, s.exp))
        assertEquals(listOf(false, true), listOf(s.b, s.bf))
        assertEquals(listOf("lit", "q"), listOf(s.s, s.id))
        assertEquals(Spelling.V1, s.e)
        assertEquals("L", s.inner!!.label)
        assertNull(s.nothing)
        assertNull(s.emptyObj!!.n)

        val m = client.queries.literalsMixed(listOf(8), OnlyOne.ONLY).echoArgs
        assertEquals(listOf(8), m.a)
        assertEquals(listOf(Spelling.A, Spelling.B2), m.e)
    }
}
