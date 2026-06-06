package dev.graphlink.test

import dev.graphlink.test.generated.client.DefaultGraphLinkWebSocketAdapter
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.collect
import org.junit.jupiter.api.Timeout
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.TimeoutException
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertTrue

class SubscriptionReconnectTest {

    companion object {
        private const val PORT_HALT   = 9996
        private const val PORT_BEFORE = 9993

        private fun jarPath(): String =
            System.getenv("SERVER_JAR")?.takeIf { it.isNotBlank() }
                ?: "../../spring_server/build/libs/graphlink-test-server-0.0.1.jar"

        private fun wsUrl(port: Int)   = "ws://localhost:$port/graphql"
        private fun httpUrl(port: Int) = "http://localhost:$port/graphql"
    }

    // ── Test 1: stream resumes after server halt ─────────────────────────────

    @Test
    @Timeout(value = 2, unit = TimeUnit.MINUTES)
    fun counterTick_resumesAfterServerHalt() {
        runBlocking {
            withContext(Dispatchers.IO) {
                killPort(PORT_HALT)
                startJar(PORT_HALT)
            }

            val codec = KotlinxSerializationGraphLinkJsonCodec()
            val wsAdapter = DefaultGraphLinkWebSocketAdapter(wsUrl(PORT_HALT))
            val client = GraphLinkClient(
                OkHttpGraphLinkClientAdapter(httpUrl(PORT_HALT)),
                wsAdapter,
                MockMultipartAdapter(),
                codec, codec,
            )

            val firstTickDeferred = CompletableDeferred<Unit>()
            val resumeDeferred    = CompletableDeferred<Unit>()
            var serverKilled = false

            val collectJob = launch {
                client.subscriptions.counterTick().collect { _ ->
                    if (!firstTickDeferred.isCompleted) {
                        firstTickDeferred.complete(Unit)
                    } else if (serverKilled && !resumeDeferred.isCompleted) {
                        resumeDeferred.complete(Unit)
                    }
                }
            }

            try {
                withTimeout(10_000) { firstTickDeferred.await() }

                withContext(Dispatchers.IO) { killPort(PORT_HALT) }
                serverKilled = true

                launch(Dispatchers.IO) {
                    try { startJar(PORT_HALT) } catch (_: Exception) {}
                }

                withTimeout(90_000) { resumeDeferred.await() }
            } finally {
                collectJob.cancel()
                wsAdapter.close()
                withContext(Dispatchers.IO) { killPort(PORT_HALT) }
            }
        }
    }

    // ── Test 2: subscribe before server is available ─────────────────────────

    @Test
    @Timeout(value = 2, unit = TimeUnit.MINUTES)
    fun counterTick_subscribesBeforeServerIsAvailable() {
        runBlocking {
            withContext(Dispatchers.IO) { killPort(PORT_BEFORE) }

            val codec = KotlinxSerializationGraphLinkJsonCodec()
            val wsAdapter = DefaultGraphLinkWebSocketAdapter(wsUrl(PORT_BEFORE))
            val client = GraphLinkClient(
                OkHttpGraphLinkClientAdapter(httpUrl(PORT_BEFORE)),
                wsAdapter,
                MockMultipartAdapter(),
                codec, codec,
            )

            val firstTickDeferred = CompletableDeferred<Int>()

            val collectJob = launch {
                client.subscriptions.counterTick().collect { r ->
                    if (!firstTickDeferred.isCompleted) firstTickDeferred.complete(r.counterTick)
                }
            }

            try {
                delay(1_000)

                launch(Dispatchers.IO) {
                    try { startJar(PORT_BEFORE) } catch (_: Exception) {}
                }

                val tick = withTimeout(60_000) { firstTickDeferred.await() }
                assertTrue(tick > 0, "Expected positive tick but got $tick")
            } finally {
                collectJob.cancel()
                wsAdapter.close()
                withContext(Dispatchers.IO) { killPort(PORT_BEFORE) }
            }
        }
    }

    // ── Test 3: maxReconnectAttempts=null retries indefinitely ──────────────

    @Test
    @Timeout(value = 2, unit = TimeUnit.MINUTES)
    fun counterTick_nullMaxReconnectAttemptsRetriesIndefinitely() {
        val port = 9984 // no server started — adapter just keeps retrying
        val targetAttempts = 10

        runBlocking {
            val codec = KotlinxSerializationGraphLinkJsonCodec()
            val wsAdapter = DefaultGraphLinkWebSocketAdapter(
                url = wsUrl(port),
                maxReconnectAttempts = null,
                maxReconnectDelayMs = 2_000L,
            )
            val client = GraphLinkClient(
                OkHttpGraphLinkClientAdapter(httpUrl(port)),
                wsAdapter,
                MockMultipartAdapter(),
                codec, codec,
            )

            val collectJob = launch {
                client.subscriptions.counterTick().collect {}
            }

            try {
                val deadline = System.currentTimeMillis() + 60_000L
                while (wsAdapter.reconnectAttempts < targetAttempts) {
                    if (System.currentTimeMillis() > deadline) {
                        error("Timed out — only reached ${wsAdapter.reconnectAttempts}/$targetAttempts attempts")
                    }
                    delay(500)
                    println("[test] reconnectAttempts=${wsAdapter.reconnectAttempts}")
                }
                assertTrue(wsAdapter.reconnectAttempts >= targetAttempts,
                    "Adapter must keep retrying when maxReconnectAttempts is null")
            } finally {
                collectJob.cancel()
                wsAdapter.close()
            }
        }
    }

    // ── Server lifecycle helpers ──────────────────────────────────────────────

    private fun killPort(port: Int) {
        ProcessBuilder("bash", "-c",
            "lsof -ti :$port -sTCP:LISTEN | xargs kill -9 2>/dev/null || true")
            .start().waitFor()
        Thread.sleep(500)
    }

    private fun startJar(port: Int) {
        ProcessBuilder("java", "-jar", jarPath(), "--server.port=$port")
            .apply {
                redirectOutput(ProcessBuilder.Redirect.DISCARD)
                redirectError(ProcessBuilder.Redirect.DISCARD)
            }
            .start()
        waitForPort(port)
    }

    private fun waitForPort(port: Int) {
        val deadline = System.currentTimeMillis() + 25_000
        while (System.currentTimeMillis() < deadline) {
            try {
                Socket().use { it.connect(InetSocketAddress("localhost", port), 1_000); return }
            } catch (_: IOException) {
                Thread.sleep(500)
            }
        }
        throw TimeoutException("Server on port $port did not start within 25 s")
    }
}
