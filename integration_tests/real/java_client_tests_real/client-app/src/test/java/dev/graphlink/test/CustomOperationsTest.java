package dev.graphlink.test;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.enums.*;
import dev.graphlink.test.generated.inputs.InnerInput;
import dev.graphlink.test.generated.types.*;
import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class CustomOperationsTest {

    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        client = newRealClient();
    }

    @Test
    void aFragmentThatSpreadsAnotherFragment() {
        var u = client.queries.fragNested("user-1").getGetUser();
        assertEquals(List.of("user-1", "Alice Smith"), List.of(u.getId(), u.getName()));
        assertEquals(UserStatus.ACTIVE, u.getStatus());
    }

    @Test
    void oneFragmentReusedByTwoOperations() {
        List<String> ids = client.queries.fragReuseA().getListUsers().stream().map(u -> u.getId()).collect(Collectors.toList());
        assertTrue(ids.containsAll(List.of("user-1", "user-2")));
        var one = client.queries.fragReuseB("user-2").getGetUser();
        assertEquals(List.of("user-2", "Bob Jones"), List.of(one.getId(), one.getName()));
        assertNotNull(one.getEmail());
    }

    @Test
    void aFragmentOnAnInterfaceNextToAnInlineFragment() {
        var feed = client.queries.fragOnInterface().getFeed();
        assertFalse(feed.isEmpty());
        assertTrue(feed.stream().allMatch(e -> !e.getId().isEmpty() && !e.getCreatedBy().isEmpty()));
    }

    @Test
    void severalRootFieldsSharingOneFragment() {
        var r = client.queries.multiRoot();
        assertEquals("Alice Smith", r.getFirst().getName());
        assertEquals("Bob Jones", r.getSecond().getName());
        assertTrue(r.getAll().stream().map(u -> u.getId()).collect(Collectors.toList()).containsAll(List.of("user-1", "user-2")));
    }

    @Test
    void variableDefaultsApplyWhenNotGiven() {
        assertEquals(1, client.queries.varsDefaults(null, null).getSearchUsers().size());
    }

    @Test
    void anExplicitValueReplacesTheVariableDefault() {
        var r = client.queries.varsDefaults(5, "Alice").getSearchUsers();
        assertEquals(List.of("user-1"), r.stream().map(u -> u.getId()).collect(Collectors.toList()));
    }

    @Test
    void listNestedListAndEnumVariables() {
        var r = client.queries.varsLists(
            List.of(1, 2), Arrays.asList(1, null), List.of(List.of(1), List.of(2, 3)),
            List.of(Spelling.X_Y), Arrays.asList(null, Spelling.V1)).getEchoArgs();
        assertEquals(List.of(1, 2), r.getA());
        assertEquals(Arrays.asList(1, null), r.getB());
        assertEquals(List.of(List.of(1), List.of(2, 3)), r.getC());
        assertEquals(List.of(Spelling.X_Y), r.getE());
        assertEquals(Arrays.asList(null, Spelling.V1), r.getF());
    }

    @Test
    void aNullableEnumVariable() {
        assertEquals(OnlyOne.ONLY, client.queries.varsEnum(OnlyOne.ONLY).getEchoArgs().getOne());
    }

    @Test
    void anInputObjectVariable() {
        var r = client.queries.varsInput(new InnerInput(4, "x", null)).getEchoInner();
        assertEquals(4, r.getN());
        assertEquals("x", r.getLabel());
    }

    @Test
    void nullableVersusNonNullVariables() {
        var given = client.queries.varsNullable("$d", "q").getEchoNastyArgs();
        assertEquals("$d", given.getDollar());
        assertEquals("q", given.getQuote());
        var left = client.queries.varsNullable(null, "q").getEchoNastyArgs();
        assertNull(left.getDollar());
        assertEquals("q", left.getQuote());
    }

    @Test
    void includeAndSkipWithVariables() {
        var both = client.queries.conditionalVars(true, false).getGetUser();
        assertEquals(List.of("user-1", "Alice Smith", "alice@test.com"), List.of(both.getId(), both.getName(), both.getEmail()));
        var neither = client.queries.conditionalVars(false, true).getGetUser();
        assertEquals("user-1", neither.getId());
        assertNull(neither.getName());
        assertNull(neither.getEmail());
    }

    @Test
    void includeAndSkipWithLiterals() {
        var u = client.queries.conditionalLiterals().getGetUser();
        assertEquals("Alice Smith", u.getName());
        assertNull(u.getEmail());
        assertEquals(UserStatus.ACTIVE, u.getStatus());
        assertNull(u.getPriority());
    }

    @Test
    void aliases() {
        var r = client.queries.aliasesSameField();
        assertEquals(List.of("user-1", "user-2"), List.of(r.getA().getId(), r.getB().getId()));
        var k = client.queries.aliasKeywords().getClass_();
        assertEquals(List.of("Alice Smith", "user-1"), List.of(k.getDefault_(), k.getImport_()));
        assertEquals("alice@test.com", client.queries.aliasEqualsOtherField().getGetUser().getName());
    }

    @Test
    void operationNamesThatCollide() {
        assertEquals("user-1", client.queries.user().getGetUser().getId());
        assertEquals("ph1", client.queries.photo2().getPhoto().getId());
        assertFalse(client.queries.return_().getListUsers().isEmpty());
        assertEquals("s1", client.queries.shelf().getShelf().getId());
        assertEquals("user-1", client.queries.getUserResponse().getGetUser().getId());
    }

    @Test
    void fieldArgumentsOfEveryShape() {
        assertEquals(
            List.of("tags=[a, b]", "kind=x__y", "filter={n=3, label=L}", "limit=5"),
            client.queries.shelfItems().getShelf().getItems());
        List<String> r = client.queries.shelfItemsVars(List.of("t"), Spelling.V1, new InnerInput(1, "f", null), 7).getShelf().getItems();
        assertEquals(List.of("tags=[t]", "kind=v1", "limit=7"), List.of(r.get(0), r.get(1), r.get(3)));
        List<String> defaults = client.queries.shelfItemsDefaults().getShelf().getItems();
        assertEquals("limit=2", defaults.get(defaults.size() - 1));
    }

    @Test
    void literalArgumentsOfEveryKind() {
        var l = client.queries.literalLists().getEchoArgs();
        assertEquals(List.of(1, 2, 3), l.getA());
        assertEquals(Arrays.asList(1, null), l.getB());
        assertEquals(List.of(List.of(1), List.of(2, 3)), l.getC());
        assertEquals(List.of(Spelling.A, Spelling.X_Y), l.getE());
        assertEquals(Arrays.asList(null, Spelling.V1), l.getF());
        assertEquals(List.of(Spelling.SNAKE_CASE_2), l.getG());
        assertEquals(OnlyOne.ONLY, l.getOne());

        var i = client.queries.literalInput().getEchoInput();
        assertEquals(List.of(4), i.getA());
        assertEquals(Arrays.asList(null, 5), i.getB());
        assertEquals(List.of(List.of(6)), i.getC());

        var s = client.queries.literalScalars().getEchoEverything();
        assertEquals(List.of(5, -3, 9), List.of(s.getI(), s.getNeg(), s.getBig()));
        assertEquals(List.of(2.5, 100.0), List.of(s.getF(), s.getExp()));
        assertEquals(List.of(false, true), List.of(s.getB(), s.getBf()));
        assertEquals(List.of("lit", "q"), List.of(s.getS(), s.getId()));
        assertEquals(Spelling.V1, s.getE());
        assertEquals("L", s.getInner().getLabel());
        assertNull(s.getNothing());
        assertNull(s.getEmptyObj().getN());

        var m = client.queries.literalsMixed(List.of(8), OnlyOne.ONLY).getEchoArgs();
        assertEquals(List.of(8), m.getA());
        assertEquals(List.of(Spelling.A, Spelling.B2), m.getE());
    }
}
