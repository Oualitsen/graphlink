package dev.graphlink.test;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.enums.Literal;
import dev.graphlink.test.generated.inputs.OddInput;
import dev.graphlink.test.generated.inputs.ReservedInput;
import dev.graphlink.test.generated.types.*;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class IdentifiersTest {

    private static final List<Literal> LITERALS = List.of(
        Literal.DEFAULT, Literal.CLASS, Literal.NONE, Literal.TRUE, Literal.NIL, Literal.UNDEFINED, Literal.NA_N, Literal.SELF);

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    private static void assertEchoed(Reserved r) {
        Map<String, String> fields = new LinkedHashMap<>();
        fields.put("type", r.getType());
        fields.put("default", r.getDefault_());
        fields.put("in", r.getIn());
        fields.put("is", r.getIs());
        fields.put("var", r.getVar());
        fields.put("val", r.getVal());
        fields.put("fun", r.getFun());
        fields.put("new", r.getNew_());
        fields.put("import", r.getImport_());
        fields.put("return", r.getReturn_());
        fields.put("object", r.getObject());
        fields.put("from", r.getFrom());
        fields.put("None", r.getNone());
        fields.put("True", r.getTrue_());
        fields.put("func", r.getFunc());
        fields.put("range", r.getRange());
        fields.put("self", r.getSelf());
        fields.put("Self", r.getSelf2());
        fields.put("init", r.getInit());
        fields.put("Type", r.getType2());
        fields.put("Protocol", r.getProtocol());
        fields.put("async", r.getAsync());
        fields.put("await", r.getAwait());
        fields.put("package", r.getPackage_());
        fields.put("interface", r.getInterface_());
        fields.put("enum", r.getEnum_());
        fields.put("null", r.getNull_());
        assertEquals(27, fields.size());
        fields.forEach((wire, value) -> assertEquals("v:" + wire, value, wire));
    }

    private static String[] values() {
        String[] wire = {"type", "default", "in", "is", "var", "val", "fun", "new", "import", "return", "object", "from",
            "None", "True", "func", "range", "self", "Self", "init", "Type", "Protocol", "async", "await", "package",
            "interface", "enum", "null"};
        String[] out = new String[wire.length];
        for (int i = 0; i < wire.length; i++) {
            out[i] = "v:" + wire[i];
        }
        return out;
    }

    @Test
    void reservedWordsAsArgumentNames() {
        String[] v = values();
        Reserved r = client.queries.reservedEcho(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11],
            v[12], v[13], v[14], v[15], v[16], v[17], v[18], v[19], v[20], v[21], v[22], v[23], v[24], v[25], v[26]).getReservedEcho();
        assertEchoed(r);
    }

    @Test
    void reservedWordsAsInputAndResponseFields() {
        String[] v = values();
        ReservedInput input = new ReservedInput(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11],
            v[12], v[13], v[14], v[15], v[16], v[17], v[18], v[19], v[20], v[21], v[22], v[23], v[24], v[25], v[26]);
        assertEchoed(client.queries.reservedEchoInput(input).getReservedEchoInput());
    }

    @Test
    void reservedWordsAsOperationNames() {
        assertEquals("a", client.queries.import_("a").getImport_());
        assertEquals("b", client.queries.default_("b").getDefault_());
        assertEquals("c", client.queries.new_("c").getNew_());
        assertEquals("d", client.queries.func("d").getFunc());
        assertEquals("e", client.queries.none("e").getNone());
        assertEquals("f", client.queries.self("f").getSelf());
    }

    @Test
    void literalLookingEnumValuesDecode() {
        assertEquals(LITERALS, client.queries.literals().getLiterals());
    }

    @Test
    void literalLookingEnumValuesRoundTrip() {
        for (Literal value : LITERALS) {
            assertEquals(value, client.queries.literalEcho(value, LITERALS).getLiteralEcho());
        }
    }

    @Test
    void stdlibClashingTypeNames() {
        Clashes c = client.queries.clashes().getClashes();
        assertEquals(
            List.of("error-1", "response-1", "request-1", "list-1", "map-1", "object-1", "optional-1", "date-1", "result-1", "void-1"),
            List.of(c.getError().getId(), c.getResponse().getId(), c.getRequest().getId(), c.getList().getId(),
                c.getMap().getId(), c.getObject().getId(), c.getOptional().getId(), c.getDate().getId(),
                c.getResult().getId(), c.getVoid_().getId()));
    }

    @Test
    void oddNamesRoundTrip() {
        Odd r = client.queries.oddEcho(new OddInput("user_id", "userId", "URLValue", "HTTPServer", "_leading", "trailing_",
            "v2_name", "isActive", "active", "getX", "x")).getOddEcho();
        assertEquals(
            List.of("user_id", "userId", "URLValue", "HTTPServer", "_leading", "trailing_", "v2_name", "isActive", "active", "getX", "x"),
            List.of(r.getUserId2(), r.getUserId(), r.getUrlValue(), r.getHttpServer(), r.getLeading(), r.getTrailing(),
                r.getV2Name(), r.getIsActive(), r.getActive(), r.getGetX(), r.getX()));
    }
}
