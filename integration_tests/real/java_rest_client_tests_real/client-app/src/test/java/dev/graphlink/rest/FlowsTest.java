package dev.graphlink.rest;

import static dev.graphlink.rest.Support.*;
import static org.junit.jupiter.api.Assertions.*;

import dev.graphlink.rest.generated.client.*;
import dev.graphlink.rest.generated.enums.Status;
import dev.graphlink.rest.generated.inputs.*;
import dev.graphlink.rest.generated.types.Echo;
import dev.graphlink.rest.generated.types.Product;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CompletableFuture;
import java.util.stream.Collectors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class FlowsTest {
    static class CountingStore implements GraphLinkCacheStore {
        private final InMemoryGraphLinkCacheStore inner = new InMemoryGraphLinkCacheStore();
        int sets = 0;

        @Override public void set(String key, String value) { sets++; inner.set(key, value); }
        @Override public String get(String key) { return inner.get(key); }
        @Override public void invalidate(String key) { inner.invalidate(key); }
        @Override public void invalidateAll() { inner.invalidateAll(); }
    }

    private GraphLinkClient client;
    private InMemoryGraphLinkCacheStore store;

    @BeforeEach
    void setUp() throws Exception {
        resetServer();
        store = new InMemoryGraphLinkCacheStore();
        client = newClient(store);
    }

    private ProductIn product(String name) { return new ProductIn(name, null, null, null); }

    @Test
    void productLifecycle() {
        Product created = client.mutations.createProduct(new ProductIn("Lamp", 30.0, null, List.of("home")));
        assertEquals("Lamp", created.getName());
        assertEquals(Status.ACTIVE, created.getStatus());
        assertEquals(30.0, client.queries.product(created.getId()).getPrice());
        assertEquals(List.of(created.getId()), client.queries.products(new Filter("home", null, null), null).stream().map(Product::getId).collect(Collectors.toList()));
        assertEquals(Set.of("p1", created.getId()), client.queries.products(null, List.of("p1", created.getId())).stream().map(Product::getId).collect(Collectors.toSet()));
        Product patched = client.mutations.patchProduct(created.getId(), new ProductIn("Lamp 2", 35.0, null, null));
        assertEquals(List.of("Lamp 2", 35.0), List.of(patched.getName(), patched.getPrice()));
        Product renamed = client.mutations.renameProduct(created.getId(), "Lamp 3", "n");
        assertEquals(List.of("Lamp 3", List.of("n")), List.of(renamed.getName(), renamed.getTags()));
        Product gallery = client.mutations.gallery(created.getId(), "Gallery é", List.of(uploadOf(pattern(100), "a.png"), uploadOf(pattern(200), "b.png")));
        assertEquals(List.of("Gallery é", List.of("a.png", "b.png")), List.of(gallery.getName(), gallery.getTags()));
        assertEquals("Final", client.mutations.replaceProduct(created.getId(), product("Final")).getName());
        client.mutations.deleteProduct(created.getId());
        assertEquals(404, assertThrows(RestError.class, () -> client.queries.product(created.getId())).getStatus());
        client.mutations.deleteProduct("p2");
        assertEquals(404, assertThrows(RestError.class, () -> client.mutations.deleteProduct("p2")).getStatus());
    }

    @Test
    void concurrentCalls() {
        List<CompletableFuture<Product>> futures = new ArrayList<>();
        for (int i = 0; i < 40; i++) {
            String name = "item-" + i;
            futures.add(CompletableFuture.supplyAsync(() -> client.mutations.createProduct(product(name)), POOL));
        }
        List<Product> results = futures.stream().map(CompletableFuture::join).collect(Collectors.toList());
        assertEquals(40, results.stream().map(Product::getName).collect(Collectors.toSet()).size());
        assertEquals(40, results.stream().map(Product::getId).collect(Collectors.toSet()).size());
        assertEquals(42, client.queries.products(null, null).size());
    }

    @Test
    void cacheHitsMissesAndExpiry() throws Exception {
        assertEquals(List.of(1, 1), List.of(client.queries.counter("a").getN(), client.queries.counter("a").getN()));
        assertEquals(2, client.queries.counterUncached("a").getN());
        assertEquals(1, client.queries.counter("b").getN());
        assertEquals(1, client.queries.counter("a").getN());
        assertEquals(List.of(1, 2, 3, 4), List.of(
                client.queries.counterUncached("u").getN(), client.queries.counterUncached("u").getN(),
                client.queries.counterNoCache("u").getN(), client.queries.counterNoCache("u").getN()));
        assertEquals(1, client.queries.counterShort("s").getN());
        assertEquals(1, client.queries.counterShort("s").getN());
        Thread.sleep(1300);
        assertEquals(2, client.queries.counterShort("s").getN());
    }

    @Test
    void storesAreSharedOnlyWhenTheSame() {
        client.queries.counter("shared");
        assertEquals(1, newClient(store).queries.counter("shared").getN());
        client.queries.counter("iso");
        assertEquals(2, newClient().queries.counter("iso").getN());
    }

    @Test
    void invalidationByTagAndAll() {
        assertEquals(1, client.queries.counter("c").getN());
        client.mutations.bump("c");
        assertEquals(102, client.queries.counter("c").getN());
        assertEquals(1, client.queries.counterOther("o").getN());
        assertEquals(2, client.queries.counter("o").getN());
        client.mutations.bump("o");
        assertEquals(1, client.queries.counterOther("o").getN());
        assertTrue(client.queries.counter("o").getN() > 100);
        client.queries.counter("x");
        client.queries.counterOther("x");
        client.mutations.resetAll("x");
        assertEquals(1, client.queries.counter("x").getN());
        assertEquals(2, client.queries.counterOther("x").getN());
    }

    @Test
    void failedMutationDoesNotInvalidateAndNoContentDoes() {
        client.queries.counter("f");
        assertThrows(RestError.class, () -> client.mutations.bumpFails(500));
        assertEquals(1, client.queries.counter("f").getN());
        client.queries.counter("g");
        client.mutations.bumpFails(204);
        assertEquals(2, client.queries.counter("g").getN());
    }

    @Test
    void failuresAreNotCached() {
        CountingStore writes = new CountingStore();
        GraphLinkClient c = newClient(writes);
        assertThrows(RestError.class, () -> c.queries.cachedStatus(500));
        assertEquals(0, writes.sets);
        assertEquals("p1", c.queries.cachedStatus(200).getId());
        assertEquals(1, writes.sets);
        CountingStore bad = new CountingStore();
        GraphLinkClient b = newClient(bad);
        assertThrows(Exception.class, () -> b.queries.cachedBad());
        assertThrows(Exception.class, () -> b.queries.cachedBad());
        assertEquals(0, bad.sets);
    }

    @Test
    void anEmptyResponseToACachedNullableQueryIsNullAndIsNotCached() {
        CountingStore writes = new CountingStore();
        GraphLinkClient c = newClient(writes);
        assertNull(c.queries.cachedStatus(204));
        assertNull(c.queries.cachedStatus(204));
        assertEquals(0, writes.sets);
    }

    @Test
    void staleIfOfflineServesTheExpiredEntryOnTransportFailureOnly() throws Exception {
        client.queries.counterOffline("off");
        client.queries.counterShort("off2");
        client.queries.counter("fresh");
        Thread.sleep(1300);
        GraphLinkClient offline = newClient("http://127.0.0.1:1", store);
        assertEquals(1, offline.queries.counterOffline("off").getN());
        Exception failure = assertThrows(Exception.class, () -> offline.queries.counterShort("off2"));
        assertFalse(failure instanceof RestError);
        assertEquals(1, offline.queries.counter("fresh").getN());
        Exception never = assertThrows(Exception.class, () -> offline.queries.counter("never"));
        assertFalse(never instanceof RestError);
    }

    @Test
    void baseUrlPrefixes() {
        assertEquals("/api/echo/scalars/p", newClient(SERVER_URL + "/api").queries.eScalars("p", null, null, null, null, null, null, null).getPath());
        assertEquals("/api/echo/scalars/p", newClient(SERVER_URL + "/api/").queries.eScalars("p", null, null, null, null, null, null, null).getPath());
        assertEquals("/echo/scalars/p", newClient(SERVER_URL + "/").queries.eScalars("p", null, null, null, null, null, null, null).getPath());
    }

    @Test
    void transportErrorsAreNotRestErrors() {
        GraphLinkClient dead = newClient("http://127.0.0.1:1");
        Exception failure = assertThrows(Exception.class, () -> dead.queries.eAccept());
        assertFalse(failure instanceof RestError);
        assertEquals("GET", client.queries.eAccept().getMethod());
    }

    @Test
    void concurrentRequestsDoNotMixTheirData() {
        List<CompletableFuture<Echo>> futures = new ArrayList<>();
        for (int i = 0; i < 60; i++) {
            int n = i;
            futures.add(CompletableFuture.supplyAsync(() -> client.queries.eScalars("id" + n, null, n, null, null, null, null, null), POOL));
        }
        for (int i = 0; i < 60; i++) {
            Echo e = futures.get(i).join();
            assertEquals("/echo/scalars/id" + i, e.getPath());
            assertEquals("" + i, queryValue(e, "i"));
        }
    }

    @Test
    void mixedRequestKindsInParallel() {
        var get = CompletableFuture.supplyAsync(() -> client.queries.eAccept(), POOL);
        var json = CompletableFuture.supplyAsync(() -> client.mutations.eJson(product("x")), POOL);
        var form = CompletableFuture.supplyAsync(() -> client.mutations.eForm("f", null, null, null, null, null), POOL);
        var multipart = CompletableFuture.supplyAsync(() -> client.mutations.eMultipart("t", null, null, null, null), POOL);
        var raw = CompletableFuture.supplyAsync(() -> client.mutations.eRaw(uploadOf(pattern(1000))), POOL);
        var blob = CompletableFuture.supplyAsync(() -> client.queries.blob(2000).bytes(), POOL);
        assertEquals("GET", get.join().getMethod());
        assertTrue(json.join().getContentType().startsWith("application/json"));
        assertEquals("f", formValue(form.join(), "name"));
        assertEquals("t", part(multipart.join(), "title").getText());
        assertEquals(1000, raw.join().getBodySize());
        assertEquals(2000, blob.join().length);
    }

    @Test
    void transportEdgeCases() {
        assertEquals(List.of("p1", "p2"), client.queries.gzipped().stream().map(Product::getId).collect(Collectors.toList()));
        assertEquals(7, client.queries.redirected());
        List<Product> items = client.queries.big(50000);
        assertEquals(50000, items.size());
        assertEquals("big-49999", items.get(items.size() - 1).getName());
        Exception failure = assertThrows(Exception.class, () -> client.queries.invalidJson());
        assertFalse(failure instanceof RestError);
        RestError html = assertThrows(RestError.class, () -> client.queries.htmlError());
        assertEquals(500, html.getStatus());
        assertTrue(html.getBody().contains("Internal Server Error"));
        assertTrue(html.getHeaders().get("content-type").startsWith("text/html"));
    }
}
