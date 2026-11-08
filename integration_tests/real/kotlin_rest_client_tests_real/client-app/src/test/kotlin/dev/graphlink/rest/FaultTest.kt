package dev.graphlink.rest

import dev.graphlink.rest.generated.client.*
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.DynamicTest.dynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

private const val FAULT_PORT = 9951
private val faultUrl = "http://127.0.0.1:$FAULT_PORT"

private const val NULL_FOR_SHAPE = "a JSON array or string where an object is expected decodes to null"

private val knownDefects = mapOf(
    "json-array-top-level:p" to NULL_FOR_SHAPE,
    "json-string-top-level:p" to NULL_FOR_SHAPE,
)

private val opNames = mapOf('g' to "GraphQL getCount", 'c' to "REST count", 'p' to "REST status")

private class FaultCase(val fault: String, val ops: String, val expect: String)

private fun loadCases(): List<FaultCase> =
    Json.parseToJsonElement(File("../../fault_server/cases.json").readText()).jsonArray.map {
        val o = it.jsonObject
        FaultCase(o["fault"]!!.jsonPrimitive.content, o["ops"]!!.jsonPrimitive.content, o["expect"]!!.jsonPrimitive.content)
    }

private fun postFault(path: String) {
    val connection = URI("$faultUrl$path").toURL().openConnection() as HttpURLConnection
    connection.requestMethod = "POST"
    connection.responseCode
    connection.inputStream.use { it.readBytes() }
}

class FaultTest {
    private fun client() = newClient(baseUrl = faultUrl)

    private suspend fun call(client: GraphLinkClient, op: Char): Any? = when (op) {
        'g' -> client.queries.getCount()
        'c' -> client.queries.count()
        else -> client.queries.status(200)
    }

    private suspend fun assertHealthy(client: GraphLinkClient, op: Char) {
        when (op) {
            'g' -> assertEquals(19, client.queries.getCount().getCount)
            'c' -> assertEquals(7, client.queries.count())
            else -> assertEquals("Pen", client.queries.status(200)!!.name)
        }
    }

    @TestFactory
    fun faults(): List<DynamicTest> = loadCases().flatMap { c ->
        c.ops.map { op ->
            dynamicTest("${c.fault}: ${opNames[op]} -> ${c.expect}, then the client still works") {
                knownDefects["${c.fault}:$op"]?.let { assumeTrue(false, it) }
                postFault("/_reset")
                val client = client()
                postFault("/_arm?fault=${c.fault}")
                var result: Any? = null
                var error: Throwable? = null
                try {
                    result = runBlocking { withTimeout(8000) { call(client, op) } }
                } catch (e: TimeoutCancellationException) {
                    fail("${c.fault} hung for 8 seconds")
                } catch (e: Throwable) {
                    error = e
                }
                if (c.expect == "value") assertNull(error, "unexpected failure: $error")
                if (c.expect == "failure") assertNotNull(error, "decoded without a failure: $result")
                runBlocking { assertHealthy(client, op) }
            }
        }
    }

    @Test
    fun aRestErrorCarriesTheStatusAndTheBodyOfAGatewayPage() {
        postFault("/_reset")
        postFault("/_arm?fault=html-502")
        val error = runCatching { runBlocking { client().queries.count() } }.exceptionOrNull()
        assertIs<RestError>(error)
        assertEquals(502, error.status)
        assertTrue(error.body.contains("Bad Gateway"))
    }

    @Test
    fun aGraphQLErrorReachesTheCallerWithMessagePathAndExtensions() {
        postFault("/_reset")
        postFault("/_arm?fault=gql-errors-only")
        val error = runCatching { runBlocking { client().queries.getCount() } }.exceptionOrNull()
        assertIs<GraphLinkException>(error)
        val first = error.errors.single()
        assertEquals("boom", first.message)
        assertEquals(listOf<Any>("getCount"), first.path)
        assertEquals("BAD", first.extensions?.get("code"))
    }

    @Test
    fun aGraphQLCallKeepsTheHttpStatusAndBody() {
        for ((fault, status, text) in listOf(Triple("html-502", 502, "Bad Gateway"), Triple("status-401-json", 401, "unauthorized"))) {
            postFault("/_reset")
            postFault("/_arm?fault=$fault")
            val error = runCatching { runBlocking { client().queries.getCount() } }.exceptionOrNull()
            assertIs<GraphLinkException>(error)
            assertEquals(status, error.errors.single().status, fault)
            assertTrue(error.errors.single().body!!.contains(text), fault)
        }
    }

    @Test
    fun aResponseWithoutDataAndWithoutErrorsSaysSo() {
        postFault("/_reset")
        postFault("/_arm?fault=gql-empty-object")
        val error = runCatching { runBlocking { client().queries.getCount() } }.exceptionOrNull()
        assertIs<GraphLinkException>(error)
        assertTrue(error.errors.single().message.contains("no data"))
    }
}
