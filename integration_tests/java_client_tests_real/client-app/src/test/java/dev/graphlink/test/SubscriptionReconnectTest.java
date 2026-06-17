package dev.graphlink.test;

import dev.graphlink.test.generated.client.*;
import dev.graphlink.test.generated.types.CounterTickResponse;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

import static org.junit.jupiter.api.Assertions.*;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

class SubscriptionReconnectTest {

    private static final int PORT_HALT   = 9996;
    private static final int PORT_BEFORE = 9993;

    private static String jarPath() {
        String env = System.getenv("SERVER_JAR");
        if (env != null && !env.isBlank()) return env;
        return "../../spring_server/build/libs/graphlink-test-server-0.0.1.jar";
    }

    private static String wsUrl(int port)   { return "ws://localhost:"   + port + "/graphql"; }
    private static String httpUrl(int port) { return "http://localhost:" + port + "/graphql"; }

    // ── Test 1: stream resumes after server halt ─────────────────────────────

    @Test
    @Timeout(value = 2, unit = TimeUnit.MINUTES)
    void counterTick_resumesAfterServerHalt() throws Exception {
        log("=== counterTick_resumesAfterServerHalt START (port %d) ===", PORT_HALT);
        killPort(PORT_HALT);
        startJar(PORT_HALT);

        JacksonGraphLinkJsonCodec codec = new JacksonGraphLinkJsonCodec();
        DefaultGraphLinkWebSocketAdapter ws =
                new DefaultGraphLinkWebSocketAdapter(wsUrl(PORT_HALT));
        GraphLinkClient client = new GraphLinkClient(
                new DefaultGraphLinkClientAdapter(httpUrl(PORT_HALT)),
                null, codec, codec, ws);

        CountDownLatch firstTick  = new CountDownLatch(1);
        CountDownLatch resumeTick = new CountDownLatch(1);
        AtomicBoolean serverKilled = new AtomicBoolean(false);

        try {
            client.subscriptions.counterTick(r -> {
                log("Got tick " + r.getCounterTick());
                if (firstTick.getCount() > 0) {
                    log("  [tick] first tick received: value=%d", r.getCounterTick());
                    firstTick.countDown();
                } else if (serverKilled.get() && resumeTick.getCount() > 0) {
                    log("  [tick] resumed after reconnect: value=%d", r.getCounterTick());
                    resumeTick.countDown();
                }
            });

            log("  waiting for first tick (10 s)...");
            assertTrue(firstTick.await(10, TimeUnit.SECONDS),
                    "Timed out waiting for first counterTick");

            log("  killing server on port %d...", PORT_HALT);
            killPort(PORT_HALT);
            serverKilled.set(true);

            log("  restarting server on port %d in background...", PORT_HALT);
            Thread restartThread = new Thread(() -> {
                try {
                    startJar(PORT_HALT);
                    log("  server restarted on port %d", PORT_HALT);
                } catch (Exception e) {
                    log("  ERROR restarting server: %s", e.getMessage());
                }
            });
            restartThread.setDaemon(true);
            restartThread.start();

            log("  waiting for stream to resume (90 s)...");
            assertTrue(resumeTick.await(90, TimeUnit.SECONDS),
                    "counterTick stream did not resume after server restart");
            log("=== counterTick_resumesAfterServerHalt PASSED ===");
        } finally {
            ws.close();
            killPort(PORT_HALT);
        }
    }

    // ── Test 2: subscribe before server is available ─────────────────────────

    @Test
    @Timeout(value = 2, unit = TimeUnit.MINUTES)
    void counterTick_subscribesBeforeServerIsAvailable() throws Exception {
        log("=== counterTick_subscribesBeforeServerIsAvailable START (port %d) ===", PORT_BEFORE);
        killPort(PORT_BEFORE);

        JacksonGraphLinkJsonCodec codec = new JacksonGraphLinkJsonCodec();
        DefaultGraphLinkWebSocketAdapter ws =
                new DefaultGraphLinkWebSocketAdapter(wsUrl(PORT_BEFORE));
        GraphLinkClient client = new GraphLinkClient(
                new DefaultGraphLinkClientAdapter(httpUrl(PORT_BEFORE)),
                null, codec, codec, ws);

        CountDownLatch firstTick = new CountDownLatch(1);
        AtomicInteger tickValue  = new AtomicInteger(-1);

        try {
            log("  subscribing while server is down...");
            client.subscriptions.counterTick(r -> {
                log("  [tick] first tick received after connect: value=%d", r.getCounterTick());
                tickValue.set(r.getCounterTick());
                firstTick.countDown();
            });

            Thread.sleep(1000); // let the adapter try at least once before server comes up

            log("  starting server on port %d in background...", PORT_BEFORE);
            Thread startThread = new Thread(() -> {
                try {
                    startJar(PORT_BEFORE);
                    log("  server started on port %d", PORT_BEFORE);
                } catch (Exception e) {
                    log("  ERROR starting server: %s", e.getMessage());
                }
            });
            startThread.setDaemon(true);
            startThread.start();

            log("  waiting for first tick (60 s)...");
            assertTrue(firstTick.await(60, TimeUnit.SECONDS),
                    "Timed out — adapter did not connect after server became available");
            assertTrue(tickValue.get() > 0,
                    "Expected a positive tick value but got: " + tickValue.get());
            log("=== counterTick_subscribesBeforeServerIsAvailable PASSED ===");
        } finally {
            ws.close();
            killPort(PORT_BEFORE);
        }
    }

    // ── Test 3: maxReconnectAttempts=null retries indefinitely ──────────────

    @Test
    @Timeout(value = 2, unit = TimeUnit.MINUTES)
    void counterTick_nullMaxReconnectAttemptsRetriesIndefinitely() throws Exception {
        int port = 9988; // no server started — adapter just keeps retrying
        int targetAttempts = 10;
        log("=== nullMaxReconnectAttempts START (port %d, target=%d) ===", port, targetAttempts);

        JacksonGraphLinkJsonCodec codec = new JacksonGraphLinkJsonCodec();
        DefaultGraphLinkWebSocketAdapter ws =
                new DefaultGraphLinkWebSocketAdapter(wsUrl(port), null, 2_000L);
        GraphLinkClient client = new GraphLinkClient(
                new DefaultGraphLinkClientAdapter(httpUrl(port)),
                null, codec, codec, ws);

        try {
            client.subscriptions.counterTick(r -> {});

            long deadline = System.currentTimeMillis() + 60_000L;
            while (ws.getReconnectAttempts() < targetAttempts) {
                if (System.currentTimeMillis() > deadline) {
                    fail("Timed out — only reached " + ws.getReconnectAttempts() + "/" + targetAttempts + " attempts");
                }
                Thread.sleep(500);
                log("reconnectAttempts=%d", ws.getReconnectAttempts());
            }
            assertTrue(ws.getReconnectAttempts() >= targetAttempts,
                    "Adapter must keep retrying when maxReconnectAttempts is null");
            log("=== nullMaxReconnectAttempts PASSED ===");
        } finally {
            ws.close();
        }
    }

    // ── Server lifecycle helpers ──────────────────────────────────────────────

    private static void killPort(int port) throws Exception {
        log("  [killPort] killing process on port %d...", port);
        Process proc = new ProcessBuilder("bash", "-c",
                "lsof -ti :" + port + " -sTCP:LISTEN | xargs kill -9 2>/dev/null || true")
                .start();
        proc.waitFor();
        Thread.sleep(500);
        log("  [killPort] done (port %d)", port);
    }

    private static void startJar(int port) throws Exception {
        log("  [startJar] launching JAR on port %d: %s", port, jarPath());
        ProcessBuilder pb = new ProcessBuilder(
                "java", "-jar", jarPath(), "--server.port=" + port, "--management.server.port=-1");
        pb.redirectOutput(ProcessBuilder.Redirect.DISCARD);
        pb.redirectError(ProcessBuilder.Redirect.DISCARD);
        pb.start();
        log("  [startJar] process launched, waiting for port %d...", port);
        waitForPort(port);
        Thread.sleep(2000);
        log("  [startJar] port %d is open", port);
    }

    private static void waitForPort(int port) throws Exception {
        long deadline = System.currentTimeMillis() + 25_000;
        int attempts = 0;
        while (System.currentTimeMillis() < deadline) {
            try (Socket s = new Socket()) {
                s.connect(new InetSocketAddress("localhost", port), 1000);
                log("  [waitForPort] port %d open after %d attempt(s)", port, attempts + 1);
                return;
            } catch (IOException ignored) {
                attempts++;
                if (attempts % 4 == 0) {
                    log("  [waitForPort] still waiting for port %d (%d attempts)...", port, attempts);
                }
                Thread.sleep(500);
            }
        }
        throw new TimeoutException("Server on port " + port + " did not start within 25 s");
    }

    private static void log(String fmt, Object... args) {
        System.out.printf("[ReconnectTest] " + fmt + "%n", args);
    }

}
