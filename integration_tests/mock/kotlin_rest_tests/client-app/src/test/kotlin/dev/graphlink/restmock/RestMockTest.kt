package dev.graphlink.restmock

import dev.graphlink.restmock.generated.client.*
import dev.graphlink.restmock.generated.enums.Status
import dev.graphlink.restmock.generated.inputs.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.io.ByteArrayInputStream
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue

private val codec = KotlinxSerializationGraphLinkJsonCodec()

const val product = """{"id":"p1","name":"Pen","price":2.5,"status":"ACTIVE","tags":["a","b"]}"""

class MockRest : GLRestAdapter {
    val calls = mutableListOf<RestRequest>()
    val bodies = mutableListOf<String>()
    var failTransport = false
    private val responses = mutableMapOf<String, () -> RestResponse>()

    fun on(method: String, path: String, status: Int = 200, text: String = "", headers: Map<String, String> = emptyMap()) {
        responses["$method $path"] = { RestResponse.ofText(status, text, headers) }
    }

    val last get() = calls.last()

    override suspend fun execute(request: RestRequest): RestResponse {
        if (failTransport) throw IllegalStateException("offline")
        calls.add(request)
        when (val body = request.body) {
            is RestJsonBody -> bodies.add(body.json)
            is RestRawBody -> bodies.add(String(body.upload.stream.readBytes()))
            else -> {}
        }
        return responses["${request.method} ${request.path}"]?.invoke() ?: RestResponse.ofText(404, "no mock")
    }
}

fun q(r: RestRequest) = r.query.joinToString("&") { "${it.first}=${it.second}" }

fun bytesUpload(text: String, filename: String? = null, mimeType: String = "application/octet-stream") =
    text.toByteArray().let { GLUpload(ByteArrayInputStream(it), mimeType, it.size.toLong(), filename) }

class RestMockTest {
    private lateinit var rest: MockRest
    private lateinit var client: GraphLinkClient

    @BeforeEach
    fun setUp() {
        rest = MockRest()
        client = GraphLinkClient({ """{"data":{"ping":"pong"}}""" }, rest, codec, codec)
    }

    @Test
    fun pathVariableIsEncodedAndEnumQueryValueSent() = runBlocking {
        rest.on("GET", "/products/a%20b", text = product)
        val result = client.queries.product(id = "a b", status = Status.ARCHIVED)
        assertEquals("Pen", result!!.name)
        assertEquals("GET", rest.last.method)
        assertEquals("status=ARCHIVED", q(rest.last))
        assertEquals("application/json", rest.last.headers["Accept"])
        assertNull(rest.last.body)
        assertFalse(rest.last.headers.containsKey("Content-Type"))
    }

    @Test
    fun defaultsAreSentListsRepeatInputSpreadsHeaderSpreads() = runBlocking {
        rest.on("GET", "/products", text = "[$product]")
        client.queries.products(filter = Filter(tag = "x", minPrice = 3.0), ids = listOf("1", "2"), auth = Auth(token = "t", requestId = "r1"))
        assertEquals("tag=x&minPrice=3.0&page=1&ids=1&ids=2", q(rest.last))
        assertEquals("t", rest.last.headers["token"])
        assertEquals("r1", rest.last.headers["X-Request-Id"])
    }

    @Test
    fun nullOptionalArgumentsAreOmitted() = runBlocking {
        rest.on("GET", "/products", text = "[]")
        client.queries.products()
        assertEquals("page=1", q(rest.last))
    }

    @Test
    fun flatObjectsInAListUseIndexedKeys() = runBlocking {
        rest.on("GET", "/products/search", text = """{"data":{"total":1,"items":[$product]}}""")
        val page = client.queries.search(q = "pen", groups = listOf(Group(name = "g", ids = listOf(1, 2)), Group(name = "h")), tags = listOf("x", "y"))
        assertEquals("q=pen&groups.0.name=g&groups.0.ids=1&groups.0.ids=2&groups.1.name=h&tags=x&tags=y", q(rest.last))
        assertEquals(1, page.total)
        assertEquals("p1", page.items.single().id)
    }

    @Test
    fun jsonBodyFormBodyMultipartAndRaw() = runBlocking {
        rest.on("POST", "/products", status = 201, text = product)
        assertEquals("p1", client.mutations.createProduct(input = ProductIn(name = "Pen", price = 2.5)).id)
        assertEquals(mapOf("name" to "Pen", "price" to 2.5), codec.decode(rest.bodies.single()).filterKeys { it == "name" || it == "price" })
        assertEquals("application/json", rest.last.headers["Content-Type"])

        rest.on("POST", "/products/p1/rename", text = product)
        client.mutations.rename(id = "p1", name = "New")
        val form = rest.last.body as RestFormBody
        assertEquals(listOf("name=New"), form.fields.map { "${it.first}=${it.second}" })
        assertEquals("application/x-www-form-urlencoded", rest.last.headers["Content-Type"])

        rest.on("POST", "/products/p1/gallery", text = product)
        client.mutations.gallery(id = "p1", title = "T", files = listOf(bytesUpload("1", "a.png"), bytesUpload("2", "b.png")))
        val multipart = rest.last.body as RestMultipartBody
        assertEquals(listOf("title", "files", "files"), multipart.parts.map { it.name })
        assertEquals("T", multipart.parts.first().value)
        assertEquals("b.png", multipart.parts.last().file!!.filename)
        assertFalse(rest.last.headers.containsKey("Content-Type"))

        rest.on("PUT", "/products/p1/avatar", status = 204)
        client.mutations.avatar(id = "p1", file = bytesUpload("bytes", mimeType = "image/png"))
        assertEquals("bytes", rest.bodies.last())
        assertEquals("image/png", rest.last.headers["Content-Type"])
    }

    @Test
    fun responses() = runBlocking {
        rest.on("DELETE", "/products/p1", text = "whatever")
        client.mutations.deleteProduct(id = "p1")
        rest.on("GET", "/products/p1", status = 204)
        assertNull(client.queries.product(id = "p1"))
        rest.on("GET", "/products/count")
        assertFailsWith<IllegalStateException> { client.queries.count() }
        rest.on("GET", "/products/count", text = "7")
        assertEquals(7, client.queries.count())
        rest.on("GET", "/products/p1/note", text = "hello")
        assertEquals("hello", client.queries.note(id = "p1"))
        rest.on("GET", "/products/p1", status = 404, text = "nope", headers = mapOf("x-a" to "b"))
        val error = assertFailsWith<RestError> { client.queries.product(id = "p1") }
        assertEquals(404, error.status)
        assertEquals("nope", error.body)
        assertEquals("b", error.headers["x-a"])
    }

    @Test
    fun cacheAndInvalidation() = runBlocking {
        rest.on("GET", "/products/cached/p1", text = product)
        client.queries.cached(id = "p1")
        client.queries.cached(id = "p1")
        assertEquals(1, rest.calls.size)
        rest.on("PUT", "/products/cached/p1", text = product)
        client.mutations.updateCached(id = "p1", input = ProductIn(name = "x"))
        client.queries.cached(id = "p1")
        assertEquals(2, rest.calls.count { it.method == "GET" })
        rest.on("PUT", "/products/cached/p1", status = 500, text = "boom")
        assertFailsWith<RestError> { client.mutations.updateCached(id = "p1", input = ProductIn(name = "x")) }
        client.queries.cached(id = "p1")
        assertEquals(2, rest.calls.count { it.method == "GET" })
    }

    @Test
    fun staleIfOfflineServesStaleDataOnTransportFailureOnly() = runBlocking {
        rest.on("GET", "/products/offline/p1", text = product)
        client.queries.cachedOffline(id = "p1")
        delay(1100)
        rest.failTransport = true
        assertEquals("p1", client.queries.cachedOffline(id = "p1")!!.id)
        rest.failTransport = false
        rest.on("GET", "/products/offline/p1", status = 500, text = "down")
        assertFailsWith<RestError> { client.queries.cachedOffline(id = "p1") }
    }

    @Test
    fun graphQlAndRestShareOneClient() = runBlocking {
        rest.on("GET", "/products/count", text = "3")
        assertEquals("pong", client.queries.ping().ping)
        assertEquals(3, client.queries.count())
    }

    @Test
    fun downloads() = runBlocking {
        rest.on("GET", "/products/p1/export", text = "abcdef",
            headers = mapOf("Content-Type" to "text/csv", "Content-Length" to "6", "Content-Disposition" to "attachment; filename=\"p 1.csv\""))
        val received = mutableListOf<Long>()
        val download = client.queries.export(id = "p1", onReceiveProgress = DownloadProgressCallback { r, t -> received.add(r * 100 + t) })
        assertEquals("p 1.csv", download.filename)
        assertEquals("text/csv", download.contentType)
        assertEquals(6L, download.length)
        assertEquals("*/*", rest.last.headers["Accept"])
        assertEquals("abcdef", String(download.bytes()))
        assertEquals(606L, received.last())

        rest.on("GET", "/products/p1/export", text = "x", headers = mapOf("Content-Disposition" to "attachment; filename*=UTF-8''p%201%C3%A9.csv"))
        assertEquals("p 1é.csv", client.queries.export(id = "p1").filename)

        rest.on("GET", "/products/p1/maybe", status = 204)
        assertNull(client.queries.maybeExport(id = "p1"))
        rest.on("GET", "/products/p1/export", status = 204)
        assertFailsWith<IllegalStateException> { client.queries.export(id = "p1") }
        rest.on("GET", "/products/p1/export", status = 500, text = "x")
        assertFailsWith<RestError> { client.queries.export(id = "p1") }
    }
}
