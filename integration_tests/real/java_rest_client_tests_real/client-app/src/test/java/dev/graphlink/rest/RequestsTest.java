package dev.graphlink.rest;

import static dev.graphlink.rest.Support.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.rest.generated.client.*;
import dev.graphlink.rest.generated.enums.Status;
import dev.graphlink.rest.generated.inputs.*;
import dev.graphlink.rest.generated.types.Echo;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class RequestsTest {
    private GraphLinkClient client;

    @BeforeEach
    void setUp() throws Exception {
        resetServer();
        client = newClient();
    }

    private Echo scalars(String id, String s, Integer i, Double f, Boolean b, Status st, Integer dflt, String renamed) {
        return client.queries.eScalars(id, s, i, f, b, st, dflt, renamed);
    }

    private Echo lists(List<String> tags, List<Integer> ids, List<String> empty, List<List<Integer>> matrix, List<Row> rows) {
        return client.queries.eLists(tags, ids, empty, matrix, rows);
    }

    private Echo form(String name, Integer n, List<String> tags, Meta meta, Filter filter, Meta asJson) {
        return client.mutations.eForm(name, n, tags, meta, filter, asJson);
    }

    @Test
    void everyScalarKindIsAQueryValue() {
        Echo e = scalars("x1", "hello", 3, 2.5, true, Status.ARCHIVED, null, "r");
        assertEquals("GET", e.getMethod());
        assertEquals("/echo/scalars/x1", e.getPath());
        assertEquals(List.of("s=hello", "i=3", "f=2.5", "b=true", "st=ARCHIVED", "dflt=5", "x-ren=r"), queryPairs(e));
        assertEquals(0, e.getBodySize());
        assertNull(e.getContentType());
        assertEquals("application/json", header(e, "accept"));
    }

    @Test
    void omittedOptionalIsAbsentDefaultStillGoesOut() {
        assertEquals(List.of("dflt=5"), queryPairs(scalars("x1", null, null, null, null, null, null, null)));
        assertEquals(List.of("dflt=9"), queryPairs(scalars("x1", null, null, null, null, null, 9, null)));
    }

    @Test
    void falseAndZeroAreValues() {
        Echo e = scalars("x1", "", 0, null, false, null, null, null);
        assertEquals(List.of("s=", "i=0", "b=false", "dflt=5"), queryPairs(e));
    }

    @Test
    void reservedAndNonAsciiCharactersSurvive() {
        String segment = "a b/c?d#é+%";
        String value = "a&b=c d+e/é\"%25";
        Echo e = client.queries.eSpecial(segment, value, "ü");
        assertEquals("/echo/special/" + GraphLinkRestUtils.restEncode(segment) + "/tail", e.getPath());
        assertEquals(value, queryValue(e, "q"));
        assertEquals("ü", queryValue(e, "other"));
    }

    @Test
    void emptyStringQueryValueIsKept() {
        assertEquals("", queryValue(client.queries.eSpecial("seg", "", null), "q"));
    }

    @Test
    void deleteCarriesArgumentsInTheQuery() {
        Echo e = client.queries.eDeleteQuery("d1", true);
        assertEquals("DELETE", e.getMethod());
        assertEquals("/echo/delete/d1", e.getPath());
        assertEquals(List.of("force=true"), queryPairs(e));
        assertEquals(0, e.getBodySize());
    }

    @Test
    void scalarListsRepeatTheKeyAndEmptyListsSendNothing() {
        Echo e = lists(List.of("a", "b c"), List.of(1, 2, 3), Collections.emptyList(), null, null);
        assertEquals(List.of("tags=a", "tags=b c", "ids=1", "ids=2", "ids=3"), queryPairs(e));
        assertNull(queryValue(e, "empty"));
    }

    @Test
    void matrixUsesIndexedKeys() {
        Echo e = lists(null, null, null, List.of(List.of(1, 2), List.of(3)), null);
        assertEquals(List.of("matrix.0.0=1", "matrix.0.1=2", "matrix.1.0=3"), queryPairs(e));
    }

    @Test
    void listOfObjectsUsesIndexedKeys() {
        Echo e = lists(null, null, null, null, List.of(new Row("r0", List.of(1, 2)), new Row("r1", null)));
        assertEquals(List.of("rows.0.ids=1", "rows.0.ids=2", "rows.0.name=r0", "rows.1.name=r1"), queryPairs(e));
    }

    @Test
    void listItemsWithReservedCharactersRoundTrip() {
        Echo e = lists(List.of("a&b", "c=d", "e f", "é"), null, null, null, null);
        assertEquals("a&b|c=d|e f|é", e.getQuery().stream().filter(p -> p.getName().equals("tags")).map(p -> p.getValue()).collect(Collectors.joining("|")));
    }

    @Test
    void inputIsSpreadByDefault() {
        Echo e = client.queries.eObjects(new Filter("x", 3.0, Status.ACTIVE), null, null);
        assertEquals(List.of("tag=x", "minPrice=3.0", "status=ACTIVE"), queryPairs(e));
        assertEquals(List.of("tag=x"), queryPairs(client.queries.eObjects(new Filter("x", null, null), null, null)));
    }

    @Test
    void flatNestsWithTheSeparatorAtAnyDepth() {
        Meta meta = new Meta("m", List.of("t1", "t2"), new Address("Oran", "Rue 1", new Geo(35.7, -0.6)));
        Echo e = client.queries.eObjects(null, meta, null);
        assertEquals(
                List.of("meta.address.city=Oran", "meta.address.geo.lat=35.7", "meta.address.geo.lng=-0.6", "meta.address.street=Rue 1", "meta.name=m", "meta.tags=t1", "meta.tags=t2"),
                queryPairs(e));
    }

    @Test
    @SuppressWarnings("unchecked")
    void jsonEncodingSendsOneKey() {
        Echo e = client.queries.eObjects(null, null, new Meta("m", List.of("a"), new Address("c", null, null)));
        assertEquals(List.of("j"), e.getQuery().stream().map(p -> p.getName()).collect(Collectors.toList()));
        Map<String, Object> json = (Map<String, Object>) parseJson(queryValue(e, "j"));
        assertEquals("m", json.get("name"));
        assertEquals(List.of("a"), json.get("tags"));
        assertEquals("c", ((Map<String, Object>) json.get("address")).get("city"));
    }

    @Test
    void headerArgumentsUseDeclaredNames() {
        Echo e = client.queries.eHeaders("t-1", new Trace("tr", "sp"), null, null);
        assertEquals("t-1", header(e, "X-Tenant"));
        assertEquals("tr", header(e, "X-Trace-Id"));
        assertEquals("sp", header(e, "X-Span-Id"));
        Echo none = client.queries.eHeaders("t", new Trace("tr", null), null, null);
        assertNull(header(none, "X-Span-Id"));
        assertNull(header(none, "X-Opt"));
        assertEquals("admin,ops", header(client.queries.eHeaders("t", null, List.of("admin", "ops"), null), "X-Roles"));
    }

    @Test
    void acceptDefaultsToJsonAndCanBeOverridden() {
        assertEquals("application/json", header(client.queries.eAccept(), "accept"));
        assertEquals("application/vnd.test+json", header(client.queries.eAcceptOverride(), "accept"));
        assertNull(client.queries.eAccept().getContentType());
    }

    @Test
    void headersProviderIsConsultedForEveryRequestAndArgumentWins() {
        AtomicInteger calls = new AtomicInteger();
        GraphLinkClient c = newClient(() -> Map.of("X-Provider", "call-" + calls.incrementAndGet(), "X-Tenant", "from-provider"));
        assertEquals("call-1", header(c.queries.eAccept(), "X-Provider"));
        assertEquals("call-2", header(c.queries.eAccept(), "X-Provider"));
        assertEquals("from-arg", header(c.queries.eHeaders("from-arg", null, null, null), "X-Tenant"));
    }

    @Test
    void authThroughTheProvider() {
        RestError error = assertThrows(RestError.class, () -> client.queries.authCheck(null));
        assertEquals(401, error.getStatus());
        assertEquals("Bearer", error.getHeaders().get("www-authenticate"));
        GraphLinkClient c = newClient(() -> Map.of("Authorization", "Bearer secret"));
        var who = c.queries.authCheck("acme");
        assertEquals("ann", who.getUser());
        assertEquals("acme", who.getTenant());
    }

    private ProductIn product(String name) { return new ProductIn(name, null, null, null); }

    @Test
    @SuppressWarnings("unchecked")
    void jsonBodyIsTheArgumentItself() {
        Echo e = client.mutations.eJson(new ProductIn("Pen", 2.5, Status.ARCHIVED, List.of("a", "b")));
        assertEquals("POST", e.getMethod());
        assertEquals("/echo/json", e.getPath());
        assertTrue(e.getContentType().startsWith("application/json"));
        Map<String, Object> json = (Map<String, Object>) bodyJson(e);
        assertEquals("Pen", json.get("name"));
        assertEquals(2.5, json.get("price"));
        assertEquals("ARCHIVED", json.get("status"));
        assertEquals(List.of("a", "b"), json.get("tags"));
        assertFalse(json.containsKey("body"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void listAndEmptyListBodies() {
        List<Object> list = (List<Object>) bodyJson(client.mutations.eJsonList(List.of(product("a"), product("b"))));
        assertEquals(List.of("a", "b"), list.stream().map(o -> ((Map<String, Object>) o).get("name")).collect(Collectors.toList()));
        assertEquals(Collections.emptyList(), bodyJson(client.mutations.eJsonList(Collections.emptyList())));
    }

    @Test
    @SuppressWarnings("unchecked")
    void optionalBodyAndContentType() {
        Echo none = client.mutations.eJsonOptional(null);
        assertEquals(0, none.getBodySize());
        assertNull(none.getContentType());
        assertEquals("x", ((Map<String, Object>) bodyJson(client.mutations.eJsonOptional(product("x")))).get("name"));
        assertTrue(client.mutations.eJsonType(product("x")).getContentType().startsWith("application/vnd.test+json"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void nonAsciiAndLargeBodies() {
        String name = "é漢😀 \"quoted\" \\ back\nline";
        Echo e = client.mutations.eJson(product(name));
        assertEquals(name, ((Map<String, Object>) bodyJson(e)).get("name"));
        assertEquals(e.getBodyText().getBytes(java.nio.charset.StandardCharsets.UTF_8).length, e.getBodySize());
        List<String> tags = new ArrayList<>();
        for (int i = 0; i < 20000; i++) tags.add("tag-" + i);
        Echo big = client.mutations.eJson(new ProductIn("big", null, null, tags));
        assertEquals(20000, ((List<Object>) ((Map<String, Object>) bodyJson(big)).get("tags")).size());
    }

    @Test
    void methodsPathsAndCombinedRoles() {
        Echo put = client.mutations.ePut("a b", product("x"));
        assertEquals(List.of("PUT", "/echo/put/a%20b"), List.of(put.getMethod(), put.getPath()));
        Echo patch = client.mutations.ePatch("p", product("x"));
        assertEquals(List.of("PATCH", "/echo/patch/p"), List.of(patch.getMethod(), patch.getPath()));
        Echo combined = client.mutations.eHeaderBody("i1", "acme", product("x"));
        assertEquals("/echo/hb/i1", combined.getPath());
        assertEquals("acme", header(combined, "x-tenant"));
    }

    @Test
    @SuppressWarnings("unchecked")
    void formBody() {
        Echo e = form("Pen", 3, null, null, null, null);
        assertTrue(e.getContentType().startsWith("application/x-www-form-urlencoded"));
        assertEquals(List.of("name=Pen", "n=3"), formPairs(e));
        String value = "a&b=c d+e%f/é😀\n";
        assertEquals(value, formValue(form(value, null, null, null, null, null), "name"));
        assertEquals(List.of("name=n", "tags=x", "tags=y z"), formPairs(form("n", null, List.of("x", "y z"), null, null, null)));
        assertEquals(
                List.of("name=n", "meta.address.city=Oran", "meta.name=m"),
                formPairs(form("n", null, null, new Meta("m", null, new Address("Oran", null, null)), null, null)));
        assertEquals(List.of("name=n", "tag=t", "minPrice=1.0"), formPairs(form("n", null, null, null, new Filter("t", 1.0, null), null)));
        assertEquals("m", ((Map<String, Object>) parseJson(formValue(form("n", null, null, null, null, new Meta("m", null, null)), "j"))).get("name"));
        assertEquals(List.of("name=n"), formPairs(form("n", null, null, null, null, null)));
    }

    @Test
    void emptyFormHasNoBodyNorContentType() {
        Echo e = client.mutations.eFormEmpty(null, null);
        assertEquals(0, e.getBodySize());
        assertNull(e.getContentType());
        assertEquals(List.of("b=0"), formPairs(client.mutations.eFormEmpty(null, 0)));
    }
}
