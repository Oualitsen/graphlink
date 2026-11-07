package dev.graphlink.test;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.enums.Mood;
import dev.graphlink.test.generated.enums.Spelling;
import dev.graphlink.test.generated.inputs.*;
import dev.graphlink.test.generated.types.*;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class LiteralsTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    private static void assertNasty(NastyEcho r) {
        assertEquals("cost $5 and ${x} and $$", r.getDollar());
        assertEquals("say \"hi\" it's", r.getQuote());
        assertEquals("C:\\dir\\file\\n", r.getBackslash());
        assertEquals("line1\nline2\ttab", r.getNewline());
        assertEquals("100% {braces} {{x}} %s %d", r.getPercent());
        assertEquals("a */ b // c /* d", r.getComments());
        assertEquals("\"\"\" ''' ```", r.getTriple());
        assertEquals("café 中 😀", r.getUnicode());
        assertEquals("é中😀", r.getNonAscii());
    }

    @Test
    void stringDefaultsOnOperationArguments() {
        assertNasty(client.queries.echoNastyArgs(null, null, null, null, null, null, null, null, null).getEchoNastyArgs());
    }

    @Test
    void stringDefaultsOnInputFieldsThroughAnInputDefaultingToEmptyObject() {
        assertNasty(client.queries.echoNasty(null).getEchoNasty());
    }

    @Test
    void anExplicitValueReplacesTheDefault() {
        NastyEcho r = client.queries.echoNastyArgs("$y", null, null, null, null, null, null, null, null).getEchoNastyArgs();
        assertEquals("$y", r.getDollar());
        assertEquals("say \"hi\" it's", r.getQuote());
    }

    @Test
    void stringLiteralsWrittenInlineInAnOperation() {
        var r = client.queries.nastyLiteral().getEchoNastyArgs();
        assertEquals("cost $5 ${x}", r.getDollar());
        assertEquals("say \"hi\"", r.getQuote());
        assertEquals("C:\\dir", r.getBackslash());
        assertEquals("a\nb", r.getNewline());
        assertEquals("é😀", r.getUnicode());
        assertEquals("block \"x\" ", r.getTriple());
    }

    @Test
    void defaultsOfEveryKind() {
        EverythingEcho r = client.queries.echoEverything(EverythingInput.builder().build()).getEchoEverything();
        assertEquals(List.of(42, -7, 2147483647), List.of(r.getI(), r.getNeg(), r.getBig()));
        assertEquals(List.of(3.14, 1000.0), List.of(r.getF(), r.getExp()));
        assertEquals(List.of(true, false), List.of(r.getB(), r.getBf()));
        assertEquals(List.of("x", "abc"), List.of(r.getS(), r.getId()));
        assertEquals(Spelling.X_Y, r.getE());
        assertEquals(List.of(1, 2, 3), r.getInts());
        assertEquals(List.of(List.of(1), List.of(2, 3)), r.getNested());
        assertEquals(5, r.getInner().getN());
        assertEquals("inner", r.getInner().getLabel());
        assertNull(r.getNothing());
        assertEquals(List.of(), r.getEmptyList());
        assertEquals(1, r.getEmptyObj().getN());
        assertEquals("dflt", r.getEmptyObj().getLabel());
    }

    @Test
    void anArgumentWhoseInputTypeHasItsOwnDefaults() {
        InnerEcho r = client.queries.echoInner(null).getEchoInner();
        assertEquals(9, r.getN());
        assertEquals("dflt", r.getLabel());
        assertEquals(List.of("a"), r.getTags());
    }

    @Test
    void recursiveTree() {
        Tree tree = new Tree(1, List.of(new Tree(2, List.of(new Tree(4, null))), new Tree(3, null)));
        TreeStats r = client.queries.treeStats(tree).getTreeStats();
        assertEquals(List.of(1, 2, 4, 3), r.getFlat());
        assertEquals(3, r.getDepth());
    }

    @Test
    void mutuallyRecursiveInputs() {
        Ping ping = new Ping(1, new Pong(2, new Ping(3, null)));
        assertEquals(3, client.queries.pingLength(ping).getPingLength());
    }

    @Test
    void oneOfInput() {
        assertEquals("cat:Tom", client.queries.describePet(new Pet("Tom", null)).getDescribePet());
        assertEquals("dog:3", client.queries.describePet(new Pet(null, 3)).getDescribePet());
    }

    @Test
    @SuppressWarnings("deprecation")
    void deprecatedFieldsArgumentsAndEnumValuesStillWork() {
        Legacy r = client.queries.legacy("a", "b").getLegacy();
        assertEquals("a", r.getOld());
        assertEquals("b", r.getOlder());
        assertEquals(Mood.CALM, r.getMood());
    }
}
