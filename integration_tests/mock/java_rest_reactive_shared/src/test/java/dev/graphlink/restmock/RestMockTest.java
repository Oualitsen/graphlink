package dev.graphlink.restmock;

import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.restmock.generated.client.*;
import dev.graphlink.restmock.generated.enums.Status;
import dev.graphlink.restmock.generated.inputs.*;
import dev.graphlink.restmock.generated.types.Page;
import dev.graphlink.restmock.generated.types.Product;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class RestMockTest {
    static final JacksonGraphLinkJsonCodec CODEC = new JacksonGraphLinkJsonCodec();
    static final String PRODUCT = "{\"id\":\"p1\",\"name\":\"Pen\",\"price\":2.5,\"status\":\"ACTIVE\",\"tags\":[\"a\",\"b\"]}";

    static String q(RestRequest r) {
        return r.getQuery().stream().map(e -> e.getKey() + "=" + e.getValue()).collect(Collectors.joining("&"));
    }

    static GLUpload bytesUpload(String text, String filename, String mimeType) {
        return GLUpload.fromBytes(text.getBytes(StandardCharsets.UTF_8), filename, mimeType);
    }

    static GLUpload bytesUpload(String text, String filename) { return bytesUpload(text, filename, "application/octet-stream"); }

    private MockRest rest;
    private GraphLinkClient client;

    @BeforeEach
    void setUp() {
        rest = new MockRest();
        client = new GraphLinkClient(payload -> Rx.just("{\"data\":{\"ping\":\"pong\"}}"), rest, CODEC, CODEC);
    }

    private static void assertFailsWith(Class<? extends Throwable> type, Object signal) {
        assertInstanceOf(type, signal);
    }

    @Test
    void nothingHappensUntilSubscribed() {
        rest.on("GET", "/products/count", "7");
        var pending = client.queries.count();
        assertEquals(0, rest.calls.size());
        assertEquals(7, Rx.block(pending));
        assertEquals(1, rest.calls.size());
    }

    @Test
    void pathVariableIsEncodedAndEnumQueryValueSent() {
        rest.on("GET", "/products/a%20b", PRODUCT);
        Product result = Rx.block(client.queries.product("a b", Status.ARCHIVED));
        assertEquals("Pen", result.getName());
        assertEquals("GET", rest.last().getMethod());
        assertEquals("status=ARCHIVED", q(rest.last()));
        assertEquals("application/json", rest.last().getHeaders().get("Accept"));
        assertNull(rest.last().getBody());
        assertFalse(rest.last().getHeaders().containsKey("Content-Type"));
    }

    @Test
    void defaultsAreSentListsRepeatInputSpreadsHeaderSpreads() {
        rest.on("GET", "/products", "[" + PRODUCT + "]");
        Rx.block(client.queries.products(new Filter("x", 3.0), null, new Auth("t", "r1"), List.of("1", "2")));
        assertEquals("tag=x&minPrice=3.0&page=1&ids=1&ids=2", q(rest.last()));
        assertEquals("t", rest.last().getHeaders().get("token"));
        assertEquals("r1", rest.last().getHeaders().get("X-Request-Id"));
    }

    @Test
    void nullOptionalArgumentsAreOmitted() {
        rest.on("GET", "/products", "[]");
        Rx.block(client.queries.products(null, null, null, null));
        assertEquals("page=1", q(rest.last()));
    }

    @Test
    void flatObjectsInAListUseIndexedKeys() {
        rest.on("GET", "/products/search", "{\"data\":{\"total\":1,\"items\":[" + PRODUCT + "]}}");
        Page page = Rx.block(client.queries.search("pen", List.of(new Group("g", List.of(1, 2)), new Group("h", null)), List.of("x", "y")));
        assertEquals("q=pen&groups.0.ids=1&groups.0.ids=2&groups.0.name=g&groups.1.name=h&tags=x&tags=y", q(rest.last()));
        assertEquals(1, page.getTotal());
        assertEquals("p1", page.getItems().get(0).getId());
    }

    @Test
    void jsonBodyFormBodyMultipartAndRaw() {
        rest.on("POST", "/products", 201, PRODUCT);
        assertEquals("p1", Rx.block(client.mutations.createProduct(new ProductIn("Pen", 2.5))).getId());
        Map<String, Object> sent = CODEC.decode(rest.bodies.get(0));
        assertEquals("Pen", sent.get("name"));
        assertEquals(2.5, sent.get("price"));
        assertEquals("application/json", rest.last().getHeaders().get("Content-Type"));

        rest.on("POST", "/products/p1/rename", PRODUCT);
        Rx.block(client.mutations.rename("p1", "New", null));
        RestBody.Form form = (RestBody.Form) rest.last().getBody();
        assertEquals(List.of("name=New"), form.getFields().stream().map(e -> e.getKey() + "=" + e.getValue()).collect(Collectors.toList()));
        assertEquals("application/x-www-form-urlencoded", rest.last().getHeaders().get("Content-Type"));

        rest.on("POST", "/products/p1/gallery", PRODUCT);
        Rx.block(client.mutations.gallery("p1", "T", List.of(bytesUpload("1", "a.png"), bytesUpload("2", "b.png"))));
        RestBody.Multipart multipart = (RestBody.Multipart) rest.last().getBody();
        assertEquals(List.of("title", "files", "files"), multipart.getParts().stream().map(RestPart::getName).collect(Collectors.toList()));
        assertEquals("T", multipart.getParts().get(0).getValue());
        assertEquals("b.png", multipart.getParts().get(2).getFile().getFilename());
        assertFalse(rest.last().getHeaders().containsKey("Content-Type"));

        rest.on("PUT", "/products/p1/avatar", 204);
        Rx.block(client.mutations.avatar("p1", bytesUpload("bytes", null, "image/png")));
        assertEquals("bytes", rest.bodies.get(rest.bodies.size() - 1));
        assertEquals("image/png", rest.last().getHeaders().get("Content-Type"));
    }

    @Test
    void responsesAreSignals() {
        rest.on("DELETE", "/products/p1", "whatever");
        assertNull(Rx.failure(client.mutations.deleteProduct("p1")));

        rest.on("GET", "/products/p1", 204);
        assertNull(Rx.block(client.queries.product("p1", null)));

        rest.on("GET", "/products/count", "");
        assertFailsWith(IllegalStateException.class, Rx.failure(client.queries.count()));
        rest.on("GET", "/products/count", "7");
        assertEquals(7, Rx.block(client.queries.count()));

        rest.on("GET", "/products/p1/note", "hello");
        assertEquals("hello", Rx.block(client.queries.note("p1")));

        rest.on("GET", "/products/p1", 404, "nope", Map.of("x-a", "b"));
        RestError error = assertInstanceOf(RestError.class, Rx.failure(client.queries.product("p1", null)));
        assertEquals(404, error.getStatus());
        assertEquals("nope", error.getBody());
        assertEquals("b", error.getHeaders().get("x-a"));
    }

    @Test
    void cacheAndInvalidation() {
        rest.on("GET", "/products/cached/p1", PRODUCT);
        Rx.block(client.queries.cached("p1"));
        Rx.block(client.queries.cached("p1"));
        assertEquals(1, rest.calls.size());
        rest.on("PUT", "/products/cached/p1", PRODUCT);
        Rx.block(client.mutations.updateCached("p1", new ProductIn("x", null)));
        Rx.block(client.queries.cached("p1"));
        assertEquals(2, rest.calls.stream().filter(c -> c.getMethod().equals("GET")).count());
        rest.on("PUT", "/products/cached/p1", 500, "boom");
        assertFailsWith(RestError.class, Rx.failure(client.mutations.updateCached("p1", new ProductIn("x", null))));
        Rx.block(client.queries.cached("p1"));
        assertEquals(2, rest.calls.stream().filter(c -> c.getMethod().equals("GET")).count());
    }

    @Test
    void anEmptyCachedResultIsNullAndIsNotCached() {
        rest.on("GET", "/products/cached/none", 204);
        assertNull(Rx.block(client.queries.cached("none")));
        assertNull(Rx.block(client.queries.cached("none")));
        assertEquals(2, rest.calls.size());
    }

    @Test
    void staleIfOfflineServesStaleDataOnTransportFailureOnly() throws Exception {
        rest.on("GET", "/products/offline/p1", PRODUCT);
        Rx.block(client.queries.cachedOffline("p1"));
        Thread.sleep(1100);
        rest.failTransport = true;
        assertEquals("p1", Rx.block(client.queries.cachedOffline("p1")).getId());
        rest.failTransport = false;
        rest.on("GET", "/products/offline/p1", 500, "down");
        assertFailsWith(RestError.class, Rx.failure(client.queries.cachedOffline("p1")));
    }

    @Test
    void transportFailureIsAnErrorSignalNotARestError() {
        rest.failTransport = true;
        Throwable failure = Rx.failure(client.queries.count());
        assertInstanceOf(IllegalStateException.class, failure);
        assertFalse(failure instanceof RestError);
    }

    @Test
    void graphQlAndRestShareOneClient() {
        rest.on("GET", "/products/count", "3");
        assertEquals("pong", Rx.block(client.queries.ping()).getPing());
        assertEquals(3, Rx.block(client.queries.count()));
    }

    @Test
    void downloads() {
        rest.on("GET", "/products/p1/export", 200, "abcdef", Map.of(
                "Content-Type", "text/csv",
                "Content-Length", "6",
                "Content-Disposition", "attachment; filename=\"p 1.csv\""));
        List<Long> received = new ArrayList<>();
        GLDownload download = Rx.block(client.queries.export("p1", (r, t) -> received.add(r * 100 + t)));
        assertEquals("p 1.csv", download.getFilename());
        assertEquals("text/csv", download.getContentType());
        assertEquals(6L, download.getLength());
        assertEquals("*/*", rest.last().getHeaders().get("Accept"));
        assertEquals("abcdef", new String(download.bytes(), StandardCharsets.UTF_8));
        assertEquals(606L, received.get(received.size() - 1));

        rest.on("GET", "/products/p1/export", 200, "x", Map.of("Content-Disposition", "attachment; filename*=UTF-8''p%201%C3%A9.csv"));
        assertEquals("p 1é.csv", Rx.block(client.queries.export("p1")).getFilename());

        rest.on("GET", "/products/p1/maybe", 204);
        assertNull(Rx.block(client.queries.maybeExport("p1")));
        rest.on("GET", "/products/p1/export", 204);
        assertFailsWith(IllegalStateException.class, Rx.failure(client.queries.export("p1")));
        rest.on("GET", "/products/p1/export", 500, "x");
        assertFailsWith(RestError.class, Rx.failure(client.queries.export("p1")));
    }
}
