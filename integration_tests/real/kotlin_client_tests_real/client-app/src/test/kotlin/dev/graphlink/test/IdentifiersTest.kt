package dev.graphlink.test

import dev.graphlink.test.Fixtures.newRealClient
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.enums.*
import dev.graphlink.test.generated.inputs.*
import dev.graphlink.test.generated.types.*
import kotlinx.coroutines.test.runTest
import kotlin.test.*

class IdentifiersTest {

    private lateinit var client: GraphLinkClient

    @BeforeTest
    fun setUp() {
        client = newRealClient()
    }

    private fun v(wire: String) = "v:$wire"

    private fun assertEchoed(r: Reserved) {
        val fields = mapOf(
            "type" to r.type, "default" to r.default, "in" to r.in_, "is" to r.is_, "var" to r.var_, "val" to r.val_,
            "fun" to r.fun_, "new" to r.new, "import" to r.import, "return" to r.return_, "object" to r.object_,
            "from" to r.from, "None" to r.none, "True" to r.true_, "func" to r.func, "range" to r.range,
            "self" to r.self, "Self" to r.self2, "init" to r.init, "Type" to r.type2, "Protocol" to r.protocol,
            "async" to r.async, "await" to r.await, "package" to r.package_, "interface" to r.interface_,
            "enum" to r.enum, "null" to r.null_,
        )
        assertEquals(27, fields.size)
        fields.forEach { (wire, value) -> assertEquals(v(wire), value, wire) }
    }

    @Test
    fun reservedWordsAsArgumentNames() = runTest {
        val r = client.queries.reservedEcho(
            type = v("type"), default = v("default"), in_ = v("in"), is_ = v("is"), var_ = v("var"), val_ = v("val"),
            fun_ = v("fun"), new = v("new"), import = v("import"), return_ = v("return"), object_ = v("object"),
            from = v("from"), none = v("None"), true_ = v("True"), func = v("func"), range = v("range"),
            self = v("self"), self2 = v("Self"), init = v("init"), type2 = v("Type"), protocol = v("Protocol"),
            async = v("async"), await = v("await"), package_ = v("package"), interface_ = v("interface"),
            enum = v("enum"), null_ = v("null"),
        ).reservedEcho
        assertEchoed(r)
    }

    @Test
    fun reservedWordsAsInputAndResponseFields() = runTest {
        val r = client.queries.reservedEchoInput(
            ReservedInput(
                type = v("type"), default = v("default"), in_ = v("in"), is_ = v("is"), var_ = v("var"), val_ = v("val"),
                fun_ = v("fun"), new = v("new"), import = v("import"), return_ = v("return"), object_ = v("object"),
                from = v("from"), none = v("None"), true_ = v("True"), func = v("func"), range = v("range"),
                self = v("self"), self2 = v("Self"), init = v("init"), type2 = v("Type"), protocol = v("Protocol"),
                async = v("async"), await = v("await"), package_ = v("package"), interface_ = v("interface"),
                enum = v("enum"), null_ = v("null"),
            )
        ).reservedEchoInput
        assertEchoed(r)
    }

    @Test
    fun reservedWordsAsOperationNames() = runTest {
        assertEquals("a", client.queries.import("a").import)
        assertEquals("b", client.queries.default("b").default)
        assertEquals("c", client.queries.new("c").new)
        assertEquals("d", client.queries.func("d").func)
        assertEquals("e", client.queries.none("e").none)
        assertEquals("f", client.queries.self("f").self)
    }

    private val literals = listOf(
        Literal.DEFAULT, Literal.CLASS, Literal.NONE, Literal.TRUE, Literal.NIL, Literal.UNDEFINED, Literal.NA_N, Literal.SELF,
    )

    @Test
    fun literalLookingEnumValuesDecode() = runTest {
        assertEquals(literals, client.queries.literals().literals)
    }

    @Test
    fun literalLookingEnumValuesRoundTrip() = runTest {
        for (value in literals) {
            assertEquals(value, client.queries.literalEcho(value, literals).literalEcho)
        }
    }

    @Test
    fun stdlibClashingTypeNames() = runTest {
        val c = client.queries.clashes().clashes
        assertEquals(
            listOf("error-1", "response-1", "request-1", "list-1", "map-1", "object-1", "optional-1", "date-1", "result-1", "void-1"),
            listOf(c.error.id, c.response.id, c.request.id, c.list.id, c.map.id, c.object_.id, c.optional.id, c.date.id, c.result.id, c.void.id),
        )
    }

    @Test
    fun oddNamesRoundTrip() = runTest {
        val r = client.queries.oddEcho(
            OddInput(
                userId2 = "user_id", userId = "userId", urlValue = "URLValue", httpServer = "HTTPServer",
                leading = "_leading", trailing = "trailing_", v2Name = "v2_name", isActive = "isActive",
                active = "active", getX = "getX", x = "x",
            )
        ).oddEcho
        assertEquals(
            listOf("user_id", "userId", "URLValue", "HTTPServer", "_leading", "trailing_", "v2_name", "isActive", "active", "getX", "x"),
            listOf(r.userId2, r.userId, r.urlValue, r.httpServer, r.leading, r.trailing, r.v2Name, r.isActive, r.active, r.getX, r.x),
        )
    }
}
