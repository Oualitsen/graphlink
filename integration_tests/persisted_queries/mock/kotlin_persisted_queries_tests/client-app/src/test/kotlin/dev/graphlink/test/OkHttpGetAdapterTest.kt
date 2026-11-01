package dev.graphlink.test

import com.sun.net.httpserver.HttpServer
import dev.graphlink.test.Fixtures.kUserAliceJson
import dev.graphlink.test.generated.client.DefaultGraphLinkClientAdapter
import dev.graphlink.test.generated.client.DefaultGraphLinkGetAdapter
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.client.GraphLinkGetNotSupported
import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.URLDecoder
import kotlin.test.*

class OkHttpGetAdapterTest {
    private data class Seen(val method: String, val query: Map<String, String>, val authorization: String?)

    private lateinit var http: HttpServer
    private lateinit var server: ApqServer
    private lateinit var client: GraphLinkClient
    private val seen = mutableListOf<Seen>()
    private val codec = KotlinxSerializationGraphLinkJsonCodec()

    @BeforeTest
    fun setUp() {
        server = ApqServer()
        server.respondTo("persistedLongQuery", mapOf("getUser" to kUserAliceJson))
        http = HttpServer.create(InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0)
        http.createContext("/graphql") { exchange ->
            val params = (exchange.requestURI.rawQuery ?: "").split("&").filter { it.isNotEmpty() }.associate {
                val (k, v) = it.split("=", limit = 2)
                URLDecoder.decode(k, "UTF-8") to URLDecoder.decode(v, "UTF-8")
            }
            seen += Seen(exchange.requestMethod, params, exchange.requestHeaders.getFirst("Authorization"))
            val reply: Pair<Int, String> = try {
                val body = if (exchange.requestMethod == "GET") {
                    runBlocking { server.get.execute(codec.encode(buildMap {
                        params["operationName"]?.let { put("operationName", it) }
                        put("variables", params["variables"]?.let { codec.decode(it) } ?: emptyMap<String, Any?>())
                        put("extensions", codec.decode(params.getValue("extensions")))
                    })) }
                } else {
                    runBlocking { server.post.execute(exchange.requestBody.readBytes().decodeToString()) }
                }
                200 to body
            } catch (e: GraphLinkGetNotSupported) {
                405 to ""
            }
            val bytes = reply.second.toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/json")
            exchange.sendResponseHeaders(reply.first, if (bytes.isEmpty()) -1 else bytes.size.toLong())
            if (bytes.isNotEmpty()) exchange.responseBody.use { it.write(bytes) }
            exchange.close()
        }
        http.start()
        val url = "http://127.0.0.1:${http.address.port}/graphql"
        val headers = { mapOf("Authorization" to "Bearer token") }
        client = GraphLinkClient(
            DefaultGraphLinkClientAdapter(url, headers),
            DefaultGraphLinkGetAdapter(url, headers),
            MockWebSocketAdapter(),
            DefaultGraphLinkClientAdapter(url, headers),
            codec,
            codec,
        )
    }

    @AfterTest
    fun tearDown() = http.stop(0)

    @Test
    fun `a cold long query is a GET with the hash, then a POST with the query`() = runTest {
        val res = client.queries.persistedLongQuery("user-1")

        assertEquals("Alice Smith", res.getUser.name)
        assertEquals(listOf("GET", "POST"), seen.map { it.method })
    }

    @Test
    fun `the GET carries the operation, its variables and the hash in the URL`() = runTest {
        client.queries.persistedLongQuery("user-1")

        val query = seen.first().query
        assertEquals(setOf("operationName", "variables", "extensions"), query.keys)
        assertEquals("persistedLongQuery", query["operationName"])
        assertEquals(mapOf("id" to "user-1"), codec.decode(query.getValue("variables")))
        val persisted = codec.decode(query.getValue("extensions"))["persistedQuery"] as Map<*, *>
        assertEquals(1L, persisted["version"])
    }

    @Test
    fun `a warm query is a single GET`() = runTest {
        client.queries.persistedLongQuery("user-1")
        seen.clear()

        client.queries.persistedLongQuery("user-2")

        assertEquals(listOf("GET"), seen.map { it.method })
    }

    @Test
    fun `the headers provider applies to the GET as well`() = runTest {
        client.queries.persistedLongQuery("user-1")

        assertEquals("Bearer token", seen.first().authorization)
    }

    @Test
    fun `a 405 on GET sends the same request as a POST and remembers it`() = runTest {
        server.getSupported = false

        val res = client.queries.persistedLongQuery("user-1")

        assertEquals("Alice Smith", res.getUser.name)
        assertEquals(listOf("GET", "POST", "POST"), seen.map { it.method })
        seen.clear()

        client.queries.persistedLongQuery("user-2")
        assertEquals(listOf("POST"), seen.map { it.method })
    }
}
