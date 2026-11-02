package dev.graphlink.rest

import dev.graphlink.rest.generated.client.*
import dev.graphlink.rest.generated.enums.Status
import dev.graphlink.rest.generated.inputs.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class CountingStore(private val inner: GraphLinkCacheStore = InMemoryGraphLinkCacheStore()) : GraphLinkCacheStore by inner {
    var sets = 0

    override fun set(key: String, value: String) {
        sets++
        inner.set(key, value)
    }
}

class FlowsTest {
    private lateinit var client: GraphLinkClient
    private lateinit var store: InMemoryGraphLinkCacheStore

    @BeforeEach
    fun setUp() {
        resetServer()
        store = InMemoryGraphLinkCacheStore()
        client = newClient(store = store)
    }

    @Test
    fun productLifecycle() = runBlocking {
        val created = client.mutations.createProduct(input = ProductIn(name = "Lamp", price = 30.0, tags = listOf("home")))
        assertEquals("Lamp", created.name)
        assertEquals(Status.ACTIVE, created.status)
        assertEquals(30.0, client.queries.product(id = created.id)!!.price)
        assertEquals(listOf(created.id), client.queries.products(filter = Filter(tag = "home")).map { it.id })
        assertEquals(setOf("p1", created.id), client.queries.products(ids = listOf("p1", created.id)).map { it.id }.toSet())
        val patched = client.mutations.patchProduct(id = created.id, input = ProductIn(name = "Lamp 2", price = 35.0))
        assertEquals(listOf<Any?>("Lamp 2", 35.0), listOf(patched.name, patched.price))
        val renamed = client.mutations.renameProduct(id = created.id, name = "Lamp 3", note = "n")
        assertEquals(listOf<Any?>("Lamp 3", listOf("n")), listOf(renamed.name, renamed.tags))
        val gallery = client.mutations.gallery(
            id = created.id,
            title = "Gallery é",
            files = listOf(uploadOf(pattern(100), "a.png"), uploadOf(pattern(200), "b.png")),
        )
        assertEquals(listOf<Any?>("Gallery é", listOf("a.png", "b.png")), listOf(gallery.name, gallery.tags))
        assertEquals("Final", client.mutations.replaceProduct(id = created.id, input = ProductIn(name = "Final")).name)
        client.mutations.deleteProduct(id = created.id)
        assertEquals(404, assertFailsWith<RestError> { client.queries.product(id = created.id) }.status)
        client.mutations.deleteProduct(id = "p2")
        assertEquals(404, assertFailsWith<RestError> { client.mutations.deleteProduct(id = "p2") }.status)
    }

    @Test
    fun concurrentCalls() = runBlocking {
        val results = (0 until 40).map { async(Dispatchers.IO) { client.mutations.createProduct(input = ProductIn(name = "item-$it")) } }.awaitAll()
        assertEquals(40, results.map { it.name }.toSet().size)
        assertEquals(40, results.map { it.id }.toSet().size)
        assertEquals(42, client.queries.products().size)
    }

    @Test
    fun cacheHitsMissesAndExpiry() = runBlocking {
        assertEquals(listOf(1, 1), listOf(client.queries.counter(name = "a").n, client.queries.counter(name = "a").n))
        assertEquals(2, client.queries.counterUncached(name = "a").n)
        assertEquals(1, client.queries.counter(name = "b").n)
        assertEquals(1, client.queries.counter(name = "a").n)
        assertEquals(listOf(1, 2, 3, 4), listOf(
            client.queries.counterUncached(name = "u").n, client.queries.counterUncached(name = "u").n,
            client.queries.counterNoCache(name = "u").n, client.queries.counterNoCache(name = "u").n,
        ))
        assertEquals(1, client.queries.counterShort(name = "s").n)
        assertEquals(1, client.queries.counterShort(name = "s").n)
        delay(1300)
        assertEquals(2, client.queries.counterShort(name = "s").n)
    }

    @Test
    fun storesAreSharedOnlyWhenTheSame() = runBlocking {
        client.queries.counter(name = "shared")
        assertEquals(1, newClient(store = store).queries.counter(name = "shared").n)
        client.queries.counter(name = "iso")
        assertEquals(2, newClient().queries.counter(name = "iso").n)
    }

    @Test
    fun invalidationByTagAndAll() = runBlocking {
        assertEquals(1, client.queries.counter(name = "c").n)
        client.mutations.bump(name = "c")
        assertEquals(102, client.queries.counter(name = "c").n)
        assertEquals(1, client.queries.counterOther(name = "o").n)
        assertEquals(2, client.queries.counter(name = "o").n)
        client.mutations.bump(name = "o")
        assertEquals(1, client.queries.counterOther(name = "o").n)
        assertTrue(client.queries.counter(name = "o").n > 100)
        client.queries.counter(name = "x")
        client.queries.counterOther(name = "x")
        client.mutations.resetAll(name = "x")
        assertEquals(1, client.queries.counter(name = "x").n)
        assertEquals(2, client.queries.counterOther(name = "x").n)
    }

    @Test
    fun failedMutationDoesNotInvalidateAndNoContentDoes() = runBlocking {
        client.queries.counter(name = "f")
        assertFailsWith<RestError> { client.mutations.bumpFails(code = 500) }
        assertEquals(1, client.queries.counter(name = "f").n)
        client.queries.counter(name = "g")
        client.mutations.bumpFails(code = 204)
        assertEquals(2, client.queries.counter(name = "g").n)
    }

    @Test
    fun failuresAreNotCached() = runBlocking {
        val writes = CountingStore()
        val c = newClient(store = writes)
        assertFailsWith<RestError> { c.queries.cachedStatus(code = 500) }
        assertEquals(0, writes.sets)
        assertEquals("p1", c.queries.cachedStatus(code = 200)!!.id)
        assertEquals(1, writes.sets)
        val bad = CountingStore()
        val b = newClient(store = bad)
        assertFailsWith<Exception> { b.queries.cachedBad() }
        assertFailsWith<Exception> { b.queries.cachedBad() }
        assertEquals(0, bad.sets)
    }

    @Test
    fun staleIfOfflineServesTheExpiredEntryOnTransportFailureOnly() = runBlocking {
        client.queries.counterOffline(name = "off")
        client.queries.counterShort(name = "off2")
        client.queries.counter(name = "fresh")
        delay(1300)
        val offline = newClient(baseUrl = "http://127.0.0.1:1", store = store)
        assertEquals(1, offline.queries.counterOffline(name = "off").n)
        val failure = assertFailsWith<Exception> { offline.queries.counterShort(name = "off2") }
        assertFalse(failure is RestError)
        assertEquals(1, offline.queries.counter(name = "fresh").n)
        val never = assertFailsWith<Exception> { offline.queries.counter(name = "never") }
        assertFalse(never is RestError)
    }

    @Test
    fun baseUrlPrefixes() = runBlocking {
        assertEquals("/api/echo/scalars/p", newClient(baseUrl = "$serverUrl/api").queries.eScalars(id = "p").path)
        assertEquals("/api/echo/scalars/p", newClient(baseUrl = "$serverUrl/api/").queries.eScalars(id = "p").path)
        assertEquals("/echo/scalars/p", newClient(baseUrl = "$serverUrl/").queries.eScalars(id = "p").path)
    }

    @Test
    fun transportErrorsAreNotRestErrors() = runBlocking {
        val dead = newClient(baseUrl = "http://127.0.0.1:1")
        val failure = assertFailsWith<Exception> { dead.queries.eAccept() }
        assertFalse(failure is RestError)
        assertEquals("GET", client.queries.eAccept().method)
    }

    @Test
    fun concurrentRequestsDoNotMixTheirData() = runBlocking {
        val results = (0 until 60).map { i -> async(Dispatchers.IO) { client.queries.eScalars(id = "id$i", i = i) } }.awaitAll()
        for (i in 0 until 60) {
            assertEquals("/echo/scalars/id$i", results[i].path)
            assertEquals("$i", results[i].queryValue("i"))
        }
    }

    @Test
    fun mixedRequestKindsInParallel() = runBlocking {
        val c = client
        val get = async(Dispatchers.IO) { c.queries.eAccept() }
        val json = async(Dispatchers.IO) { c.mutations.eJson(body = ProductIn(name = "x")) }
        val form = async(Dispatchers.IO) { c.mutations.eForm(name = "f") }
        val multipart = async(Dispatchers.IO) { c.mutations.eMultipart(title = "t") }
        val raw = async(Dispatchers.IO) { c.mutations.eRaw(file = uploadOf(pattern(1000))) }
        val blob = async(Dispatchers.IO) { c.queries.blob(size = 2000).bytes() }
        assertEquals("GET", get.await().method)
        assertTrue(json.await().contentType!!.startsWith("application/json"))
        assertEquals("f", form.await().formValue("name"))
        assertEquals("t", multipart.await().part("title").text)
        assertEquals(1000, raw.await().bodySize)
        assertEquals(2000, blob.await().size)
    }

    @Test
    fun transportEdgeCases() = runBlocking {
        assertEquals(listOf("p1", "p2"), client.queries.gzipped().map { it.id })
        assertEquals(7, client.queries.redirected())
        val items = client.queries.big(n = 50000)
        assertEquals(50000, items.size)
        assertEquals("big-49999", items.last().name)
        val failure = assertFailsWith<Exception> { client.queries.invalidJson() }
        assertFalse(failure is RestError)
        val html = assertFailsWith<RestError> { client.queries.htmlError() }
        assertEquals(500, html.status)
        assertTrue(html.body.contains("Internal Server Error"))
        assertTrue(html.headers["content-type"]!!.startsWith("text/html"))
    }
}
