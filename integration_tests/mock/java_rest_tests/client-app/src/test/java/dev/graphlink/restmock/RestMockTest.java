package dev.graphlink.restmock;

import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.restmock.generated.client.*;
import dev.graphlink.restmock.generated.enums.Status;
import dev.graphlink.restmock.generated.inputs.*;
import dev.graphlink.restmock.generated.types.Page;
import dev.graphlink.restmock.generated.types.Product;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;
import java.util.stream.Collectors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class RestMockTest {
    static final JacksonGraphLinkJsonCodec CODEC = new JacksonGraphLinkJsonCodec();
    static final String PRODUCT = "{\"id\":\"p1\",\"name\":\"Pen\",\"price\":2.5,\"status\":\"ACTIVE\",\"tags\":[\"a\",\"b\"]}";

    static final class MockRest implements GLRestAdapter {
        final List<RestRequest> calls = new ArrayList<>();
        final List<String> bodies = new ArrayList<>();
        boolean failTransport = false;
        private final Map<String, Supplier<RestResponse>> responses = new HashMap<>();

        void on(String method, String path, int status, String text, Map<String, String> headers) {
            responses.put(method + " " + path, () -> RestResponse.ofText(status, text, headers));
        }

        void on(String method, String path, String text) { on(method, path, 200, text, Collections.emptyMap()); }

        void on(String method, String path, int status) { on(method, path, status, "", Collections.emptyMap()); }

        void on(String method, String path, int status, String text) { on(method, path, status, text, Collections.emptyMap()); }

        RestRequest last() { return calls.get(calls.size() - 1); }

        @Override
        public RestResponse execute(RestRequest request) {
            if (failTransport) throw new IllegalStateException("offline");
            calls.add(request);
            RestBody body = request.getBody();
            try {
                if (body instanceof RestBody.Json json) bodies.add(json.getJson());
                else if (body instanceof RestBody.Raw raw) bodies.add(new String(raw.getUpload().getStream().readAllBytes(), StandardCharsets.UTF_8));
            } catch (IOException e) {
                throw new RuntimeException(e);
            }
            Supplier<RestResponse> response = responses.get(request.getMethod() + " " + request.getPath());
            return response != null ? response.get() : RestResponse.ofText(404, "no mock");
        }
    }

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
        client = new GraphLinkClient(payload -> "{\"data\":{\"ping\":\"pong\"}}", rest, CODEC, CODEC);
    }

    @Test
    void pathVariableIsEncodedAndEnumQueryValueSent() {
        rest.on("GET", "/products/a%20b", PRODUCT);
        Product result = client.queries.product("a b", Status.ARCHIVED);
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
        client.queries.products(new Filter("x", 3.0), null, new Auth("t", "r1"), List.of("1", "2"));
        assertEquals("tag=x&minPrice=3.0&page=1&ids=1&ids=2", q(rest.last()));
        assertEquals("t", rest.last().getHeaders().get("token"));
        assertEquals("r1", rest.last().getHeaders().get("X-Request-Id"));
    }

    @Test
    void nullOptionalArgumentsAreOmitted() {
        rest.on("GET", "/products", "[]");
        client.queries.products(null, null, null, null);
        assertEquals("page=1", q(rest.last()));
    }

    @Test
    void flatObjectsInAListUseIndexedKeys() {
        rest.on("GET", "/products/search", "{\"data\":{\"total\":1,\"items\":[" + PRODUCT + "]}}");
        Page page = client.queries.search("pen", List.of(new Group("g", List.of(1, 2)), new Group("h", null)), List.of("x", "y"));
        assertEquals("q=pen&groups.0.ids=1&groups.0.ids=2&groups.0.name=g&groups.1.name=h&tags=x&tags=y", q(rest.last()));
        assertEquals(1, page.getTotal());
        assertEquals("p1", page.getItems().get(0).getId());
    }

    @Test
    void jsonBodyFormBodyMultipartAndRaw() {
        rest.on("POST", "/products", 201, PRODUCT);
        assertEquals("p1", client.mutations.createProduct(new ProductIn("Pen", 2.5)).getId());
        Map<String, Object> sent = CODEC.decode(rest.bodies.get(0));
        assertEquals("Pen", sent.get("name"));
        assertEquals(2.5, sent.get("price"));
        assertEquals("application/json", rest.last().getHeaders().get("Content-Type"));

        rest.on("POST", "/products/p1/rename", PRODUCT);
        client.mutations.rename("p1", "New", null);
        RestBody.Form form = (RestBody.Form) rest.last().getBody();
        assertEquals(List.of("name=New"), form.getFields().stream().map(e -> e.getKey() + "=" + e.getValue()).collect(Collectors.toList()));
        assertEquals("application/x-www-form-urlencoded", rest.last().getHeaders().get("Content-Type"));

        rest.on("POST", "/products/p1/gallery", PRODUCT);
        client.mutations.gallery("p1", "T", List.of(bytesUpload("1", "a.png"), bytesUpload("2", "b.png")));
        RestBody.Multipart multipart = (RestBody.Multipart) rest.last().getBody();
        assertEquals(List.of("title", "files", "files"), multipart.getParts().stream().map(RestPart::getName).collect(Collectors.toList()));
        assertEquals("T", multipart.getParts().get(0).getValue());
        assertEquals("b.png", multipart.getParts().get(2).getFile().getFilename());
        assertFalse(rest.last().getHeaders().containsKey("Content-Type"));

        rest.on("PUT", "/products/p1/avatar", 204);
        client.mutations.avatar("p1", bytesUpload("bytes", null, "image/png"));
        assertEquals("bytes", rest.bodies.get(rest.bodies.size() - 1));
        assertEquals("image/png", rest.last().getHeaders().get("Content-Type"));
    }

    @Test
    void responses() {
        rest.on("DELETE", "/products/p1", "whatever");
        client.mutations.deleteProduct("p1");
        rest.on("GET", "/products/p1", 204);
        assertNull(client.queries.product("p1", null));
        rest.on("GET", "/products/count", "");
        assertThrows(IllegalStateException.class, () -> client.queries.count());
        rest.on("GET", "/products/count", "7");
        assertEquals(7, client.queries.count());
        rest.on("GET", "/products/p1/note", "hello");
        assertEquals("hello", client.queries.note("p1"));
        rest.on("GET", "/products/p1", 404, "nope", Map.of("x-a", "b"));
        RestError error = assertThrows(RestError.class, () -> client.queries.product("p1", null));
        assertEquals(404, error.getStatus());
        assertEquals("nope", error.getBody());
        assertEquals("b", error.getHeaders().get("x-a"));
    }

    @Test
    void cacheAndInvalidation() {
        rest.on("GET", "/products/cached/p1", PRODUCT);
        client.queries.cached("p1");
        client.queries.cached("p1");
        assertEquals(1, rest.calls.size());
        rest.on("PUT", "/products/cached/p1", PRODUCT);
        client.mutations.updateCached("p1", new ProductIn("x", null));
        client.queries.cached("p1");
        assertEquals(2, rest.calls.stream().filter(c -> c.getMethod().equals("GET")).count());
        rest.on("PUT", "/products/cached/p1", 500, "boom");
        assertThrows(RestError.class, () -> client.mutations.updateCached("p1", new ProductIn("x", null)));
        client.queries.cached("p1");
        assertEquals(2, rest.calls.stream().filter(c -> c.getMethod().equals("GET")).count());
    }

    @Test
    void staleIfOfflineServesStaleDataOnTransportFailureOnly() throws Exception {
        rest.on("GET", "/products/offline/p1", PRODUCT);
        client.queries.cachedOffline("p1");
        Thread.sleep(1100);
        rest.failTransport = true;
        assertEquals("p1", client.queries.cachedOffline("p1").getId());
        rest.failTransport = false;
        rest.on("GET", "/products/offline/p1", 500, "down");
        assertThrows(RestError.class, () -> client.queries.cachedOffline("p1"));
    }

    @Test
    void graphQlAndRestShareOneClient() {
        rest.on("GET", "/products/count", "3");
        assertEquals("pong", client.queries.ping().getPing());
        assertEquals(3, client.queries.count());
    }

    @Test
    void downloads() {
        rest.on("GET", "/products/p1/export", 200, "abcdef", Map.of(
                "Content-Type", "text/csv",
                "Content-Length", "6",
                "Content-Disposition", "attachment; filename=\"p 1.csv\""));
        List<Long> received = new ArrayList<>();
        GLDownload download = client.queries.export("p1", (r, t) -> received.add(r * 100 + t));
        assertEquals("p 1.csv", download.getFilename());
        assertEquals("text/csv", download.getContentType());
        assertEquals(6L, download.getLength());
        assertEquals("*/*", rest.last().getHeaders().get("Accept"));
        assertEquals("abcdef", new String(download.bytes(), StandardCharsets.UTF_8));
        assertEquals(606L, received.get(received.size() - 1));

        rest.on("GET", "/products/p1/export", 200, "x", Map.of("Content-Disposition", "attachment; filename*=UTF-8''p%201%C3%A9.csv"));
        assertEquals("p 1é.csv", client.queries.export("p1").getFilename());

        rest.on("GET", "/products/p1/maybe", 204);
        assertNull(client.queries.maybeExport("p1"));
        rest.on("GET", "/products/p1/export", 204);
        assertThrows(IllegalStateException.class, () -> client.queries.export("p1"));
        rest.on("GET", "/products/p1/export", 500, "x");
        assertThrows(RestError.class, () -> client.queries.export("p1"));
    }
}
