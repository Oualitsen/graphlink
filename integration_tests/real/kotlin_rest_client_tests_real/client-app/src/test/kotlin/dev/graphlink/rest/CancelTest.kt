package dev.graphlink.rest

import dev.graphlink.rest.generated.client.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.Test
import java.net.HttpURLConnection
import java.net.URI
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

private val faultUrl = "http://127.0.0.1:9951"

private fun post(path: String) {
    val connection = URI("$faultUrl$path").toURL().openConnection() as HttpURLConnection
    connection.requestMethod = "POST"
    connection.responseCode
    connection.inputStream.use { it.readBytes() }
}

class CancelTest {
    private suspend fun call(client: GraphLinkClient, op: Char): Any? = when (op) {
        'g' -> client.queries.getCount()
        'c' -> client.queries.count()
        'k' -> client.queries.cachedStatus(200)
        else -> client.queries.status(200)
    }

    @Test
    fun aCancelledCallReturnsPromptlyAndLeavesTheClientUsable() = runBlocking {
        for (op in "gcpk") {
            for (mode in listOf("cancel", "timeout")) {
                post("/_reset")
                val client = newClient(baseUrl = faultUrl)
                post("/_arm?fault=slow")
                val started = System.nanoTime()
                if (mode == "timeout") {
                    assertFailsWith<TimeoutCancellationException>("$op $mode") { withTimeout(200) { call(client, op) } }
                } else {
                    val job = async { call(client, op) }
                    delay(200)
                    job.cancel()
                    assertFailsWith<CancellationException>("$op $mode") { job.await() }
                }
                val elapsedMs = (System.nanoTime() - started) / 1_000_000
                assertTrue(elapsedMs < 700, "$op $mode: waited ${elapsedMs}ms for a response nobody wanted")
                withTimeout(5000) { call(client, op) }
            }
        }
    }
}
