package dev.graphlink.test;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.concurrent.TimeoutException;

final class ServerProcess {
    private ServerProcess() {}

    static String wsUrl(int port) { return "ws://localhost:" + port + "/graphql"; }

    static String httpUrl(int port) { return "http://localhost:" + port + "/graphql"; }

    private static String jarPath() {
        String env = System.getenv("SERVER_JAR");
        if (env != null && !env.isBlank()) return env;
        return "../../spring_server/build/libs/graphlink-test-server-0.0.1.jar";
    }

    static void killPort(int port) throws Exception {
        new ProcessBuilder("bash", "-c", "lsof -ti :" + port + " -sTCP:LISTEN | xargs kill -9 2>/dev/null || true").start().waitFor();
        Thread.sleep(500);
    }

    static void startJar(int port) throws Exception {
        ProcessBuilder pb = new ProcessBuilder("java", "-jar", jarPath(), "--server.port=" + port, "--management.server.port=-1");
        pb.redirectOutput(ProcessBuilder.Redirect.DISCARD);
        pb.redirectError(ProcessBuilder.Redirect.DISCARD);
        pb.start();
        waitForPort(port);
        Thread.sleep(2000);
    }

    private static void waitForPort(int port) throws Exception {
        long deadline = System.currentTimeMillis() + 25_000;
        while (System.currentTimeMillis() < deadline) {
            try (Socket s = new Socket()) {
                s.connect(new InetSocketAddress("localhost", port), 1000);
                return;
            } catch (IOException ignored) {
                Thread.sleep(500);
            }
        }
        throw new TimeoutException("Server on port " + port + " did not start within 25 s");
    }
}
