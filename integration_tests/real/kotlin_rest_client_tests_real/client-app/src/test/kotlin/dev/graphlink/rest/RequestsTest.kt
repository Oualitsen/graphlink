package dev.graphlink.rest

import dev.graphlink.rest.generated.client.*
import dev.graphlink.rest.generated.enums.Status
import dev.graphlink.rest.generated.inputs.*
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.assertFailsWith

class RequestsTest {
    private lateinit var client: GraphLinkClient

    @BeforeEach
    fun setUp() {
        resetServer()
        client = newClient()
    }

    @Test
    fun everyScalarKindIsAQueryValue() = runBlocking {
        val e = client.queries.eScalars(id = "x1", s = "hello", i = 3, f = 2.5, b = true, st = Status.ARCHIVED, renamed = "r")
        assertEquals("GET", e.method)
        assertEquals("/echo/scalars/x1", e.path)
        assertEquals(listOf("s=hello", "i=3", "f=2.5", "b=true", "st=ARCHIVED", "dflt=5", "x-ren=r"), e.queryPairs())
        assertEquals(0, e.bodySize)
        assertNull(e.contentType)
        assertEquals("application/json", e.header("accept"))
    }

    @Test
    fun omittedOptionalIsAbsentDefaultStillGoesOut() = runBlocking {
        assertEquals(listOf("dflt=5"), client.queries.eScalars(id = "x1").queryPairs())
        assertEquals(listOf("dflt=9"), client.queries.eScalars(id = "x1", dflt = 9).queryPairs())
    }

    @Test
    fun falseAndZeroAreValues() = runBlocking {
        val e = client.queries.eScalars(id = "x1", b = false, i = 0, s = "")
        assertEquals(listOf("s=", "i=0", "b=false", "dflt=5"), e.queryPairs())
    }

    @Test
    fun reservedAndNonAsciiCharactersSurvive() = runBlocking {
        val segment = "a b/c?d#é+%"
        val value = "a&b=c d+e/é\"%25"
        val e = client.queries.eSpecial(segment = segment, q = value, other = "ü")
        assertEquals("/echo/special/${restEncode(segment)}/tail", e.path)
        assertEquals(value, e.queryValue("q"))
        assertEquals("ü", e.queryValue("other"))
    }

    @Test
    fun emptyStringQueryValueIsKept() = runBlocking {
        assertEquals("", client.queries.eSpecial(segment = "seg", q = "").queryValue("q"))
    }

    @Test
    fun deleteCarriesArgumentsInTheQuery() = runBlocking {
        val e = client.queries.eDeleteQuery(id = "d1", force = true)
        assertEquals("DELETE", e.method)
        assertEquals("/echo/delete/d1", e.path)
        assertEquals(listOf("force=true"), e.queryPairs())
        assertEquals(0, e.bodySize)
    }

    @Test
    fun scalarListsRepeatTheKeyAndEmptyListsSendNothing() = runBlocking {
        val e = client.queries.eLists(tags = listOf("a", "b c"), ids = listOf(1, 2, 3), empty = emptyList())
        assertEquals(listOf("tags=a", "tags=b c", "ids=1", "ids=2", "ids=3"), e.queryPairs())
        assertNull(e.queryValue("empty"))
    }

    @Test
    fun matrixUsesIndexedKeys() = runBlocking {
        val e = client.queries.eLists(matrix = listOf(listOf(1, 2), listOf(3)))
        assertEquals(listOf("matrix.0.0=1", "matrix.0.1=2", "matrix.1.0=3"), e.queryPairs())
    }

    @Test
    fun listOfObjectsUsesIndexedKeys() = runBlocking {
        val e = client.queries.eLists(rows = listOf(Row(name = "r0", ids = listOf(1, 2)), Row(name = "r1")))
        assertEquals(listOf("rows.0.name=r0", "rows.0.ids=1", "rows.0.ids=2", "rows.1.name=r1"), e.queryPairs())
    }

    @Test
    fun listItemsWithReservedCharactersRoundTrip() = runBlocking {
        val e = client.queries.eLists(tags = listOf("a&b", "c=d", "e f", "é"))
        assertEquals("a&b|c=d|e f|é", e.query.filter { it.name == "tags" }.joinToString("|") { it.value })
    }

    @Test
    fun inputIsSpreadByDefault() = runBlocking {
        val e = client.queries.eObjects(filter = Filter(tag = "x", minPrice = 3.0, status = Status.ACTIVE))
        assertEquals(listOf("tag=x", "minPrice=3.0", "status=ACTIVE"), e.queryPairs())
        assertEquals(listOf("tag=x"), client.queries.eObjects(filter = Filter(tag = "x")).queryPairs())
    }

    @Test
    fun flatNestsWithTheSeparatorAtAnyDepth() = runBlocking {
        val e = client.queries.eObjects(
            meta = Meta(name = "m", tags = listOf("t1", "t2"), address = Address(city = "Oran", street = "Rue 1", geo = Geo(lat = 35.7, lng = -0.6))),
        )
        assertEquals(
            listOf("meta.name=m", "meta.tags=t1", "meta.tags=t2", "meta.address.city=Oran", "meta.address.street=Rue 1", "meta.address.geo.lat=35.7", "meta.address.geo.lng=-0.6"),
            e.queryPairs(),
        )
    }

    @Test
    fun jsonEncodingSendsOneKey() = runBlocking {
        val e = client.queries.eObjects(asJson = Meta(name = "m", tags = listOf("a"), address = Address(city = "c")))
        assertEquals(listOf("j"), e.query.map { it.name })
        val json = parseJson(e.queryValue("j")!!) as Map<*, *>
        assertEquals("m", json["name"])
        assertEquals(listOf("a"), json["tags"])
        assertEquals("c", (json["address"] as Map<*, *>)["city"])
    }

    @Test
    fun headerArgumentsUseDeclaredNames() = runBlocking {
        val e = client.queries.eHeaders(tenant = "t-1", trace = Trace(traceId = "tr", spanId = "sp"))
        assertEquals("t-1", e.header("X-Tenant"))
        assertEquals("tr", e.header("X-Trace-Id"))
        assertEquals("sp", e.header("X-Span-Id"))
        val none = client.queries.eHeaders(tenant = "t", trace = Trace(traceId = "tr"))
        assertNull(none.header("X-Span-Id"))
        assertNull(none.header("X-Opt"))
        assertEquals("admin,ops", client.queries.eHeaders(tenant = "t", roles = listOf("admin", "ops")).header("X-Roles"))
    }

    @Test
    fun acceptDefaultsToJsonAndCanBeOverridden() = runBlocking {
        assertEquals("application/json", client.queries.eAccept().header("accept"))
        assertEquals("application/vnd.test+json", client.queries.eAcceptOverride().header("accept"))
        assertNull(client.queries.eAccept().contentType)
    }

    @Test
    fun headersProviderIsConsultedForEveryRequestAndArgumentWins() = runBlocking {
        var calls = 0
        val c = newClient(headers = { mapOf("X-Provider" to "call-${++calls}", "X-Tenant" to "from-provider") })
        assertEquals("call-1", c.queries.eAccept().header("X-Provider"))
        assertEquals("call-2", c.queries.eAccept().header("X-Provider"))
        assertEquals("from-arg", c.queries.eHeaders(tenant = "from-arg").header("X-Tenant"))
    }

    @Test
    fun authThroughTheProvider() = runBlocking {
        val error = assertFailsWith<RestError> { client.queries.authCheck() }
        assertEquals(401, error.status)
        assertEquals("Bearer", error.headers["www-authenticate"])
        val c = newClient(headers = { mapOf("Authorization" to "Bearer secret") })
        val who = c.queries.authCheck(tenant = "acme")
        assertEquals("ann", who.user)
        assertEquals("acme", who.tenant)
    }

    @Test
    fun jsonBodyIsTheArgumentItself() = runBlocking {
        val e = client.mutations.eJson(body = ProductIn(name = "Pen", price = 2.5, status = Status.ARCHIVED, tags = listOf("a", "b")))
        assertEquals("POST", e.method)
        assertEquals("/echo/json", e.path)
        assertTrue(e.contentType!!.startsWith("application/json"))
        val json = e.bodyJson() as Map<*, *>
        assertEquals("Pen", json["name"])
        assertEquals(2.5, json["price"])
        assertEquals("ARCHIVED", json["status"])
        assertEquals(listOf("a", "b"), json["tags"])
        assertFalse(json.containsKey("body"))
    }

    @Test
    fun listAndEmptyListBodies() = runBlocking {
        val list = client.mutations.eJsonList(body = listOf(ProductIn(name = "a"), ProductIn(name = "b"))).bodyJson() as List<*>
        assertEquals(listOf("a", "b"), list.map { (it as Map<*, *>)["name"] })
        assertEquals(emptyList<Any>(), client.mutations.eJsonList(body = emptyList()).bodyJson())
    }

    @Test
    fun optionalBodyAndContentType() = runBlocking {
        val none = client.mutations.eJsonOptional()
        assertEquals(0, none.bodySize)
        assertNull(none.contentType)
        assertEquals("x", (client.mutations.eJsonOptional(body = ProductIn(name = "x")).bodyJson() as Map<*, *>)["name"])
        assertTrue(client.mutations.eJsonType(body = ProductIn(name = "x")).contentType!!.startsWith("application/vnd.test+json"))
    }

    @Test
    fun nonAsciiAndLargeBodies() = runBlocking {
        val name = "é漢😀 \"quoted\" \\ back\nline"
        val e = client.mutations.eJson(body = ProductIn(name = name))
        assertEquals(name, (e.bodyJson() as Map<*, *>)["name"])
        assertEquals(e.bodyText!!.toByteArray().size, e.bodySize)
        val tags = List(20000) { "tag-$it" }
        val big = client.mutations.eJson(body = ProductIn(name = "big", tags = tags))
        assertEquals(20000, ((big.bodyJson() as Map<*, *>)["tags"] as List<*>).size)
    }

    @Test
    fun methodsPathsAndCombinedRoles() = runBlocking {
        val put = client.mutations.ePut(id = "a b", body = ProductIn(name = "x"))
        assertEquals(listOf("PUT", "/echo/put/a%20b"), listOf(put.method, put.path))
        val patch = client.mutations.ePatch(id = "p", body = ProductIn(name = "x"))
        assertEquals(listOf("PATCH", "/echo/patch/p"), listOf(patch.method, patch.path))
        val combined = client.mutations.eHeaderBody(id = "i1", tenant = "acme", body = ProductIn(name = "x"))
        assertEquals("/echo/hb/i1", combined.path)
        assertEquals("acme", combined.header("x-tenant"))
    }

    @Test
    fun formBody() = runBlocking {
        val e = client.mutations.eForm(name = "Pen", n = 3)
        assertTrue(e.contentType!!.startsWith("application/x-www-form-urlencoded"))
        assertEquals(listOf("name=Pen", "n=3"), e.formPairs())
        val value = "a&b=c d+e%f/é😀\n"
        assertEquals(value, client.mutations.eForm(name = value).formValue("name"))
        assertEquals(listOf("name=n", "tags=x", "tags=y z"), client.mutations.eForm(name = "n", tags = listOf("x", "y z")).formPairs())
        assertEquals(
            listOf("name=n", "meta.name=m", "meta.address.city=Oran"),
            client.mutations.eForm(name = "n", meta = Meta(name = "m", address = Address(city = "Oran"))).formPairs(),
        )
        assertEquals(listOf("name=n", "tag=t", "minPrice=1.0"), client.mutations.eForm(name = "n", filter = Filter(tag = "t", minPrice = 1.0)).formPairs())
        assertEquals("m", (parseJson(client.mutations.eForm(name = "n", asJson = Meta(name = "m")).formValue("j")!!) as Map<*, *>)["name"])
        assertEquals(listOf("name=n"), client.mutations.eForm(name = "n").formPairs())
    }

    @Test
    fun emptyFormHasNoBodyNorContentType() = runBlocking {
        val e = client.mutations.eFormEmpty()
        assertEquals(0, e.bodySize)
        assertNull(e.contentType)
        assertEquals(listOf("b=0"), client.mutations.eFormEmpty(b = 0).formPairs())
    }
}
