package dev.graphlink.upload;

import com.sun.net.httpserver.HttpServer;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** GraphQL endpoint that records every multipart request as it arrived on the wire. */
public final class RecordingServer implements AutoCloseable {

    public record Part(String name, String filename, String contentType, byte[] bytes) {
        public String sha256() { return Sha.of(bytes); }
        public String text() { return new String(bytes, StandardCharsets.UTF_8); }
    }

    public record Received(long contentLength, boolean chunked, List<Part> parts) {
        public Part part(String name) {
            return parts.stream().filter(p -> p.name().equals(name)).findFirst().orElseThrow();
        }
    }

    public final List<Received> requests = new CopyOnWriteArrayList<>();
    private final HttpServer server;

    public RecordingServer() throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/graphql", exchange -> {
            byte[] body = exchange.getRequestBody().readAllBytes();
            String contentType = exchange.getRequestHeaders().getFirst("Content-Type");
            String length = exchange.getRequestHeaders().getFirst("Content-Length");
            String encoding = exchange.getRequestHeaders().getFirst("Transfer-Encoding");
            Matcher boundary = Pattern.compile("boundary=([^;]+)").matcher(contentType == null ? "" : contentType);
            List<Part> parts = boundary.find() ? parse(body, boundary.group(1)) : List.of();
            requests.add(new Received(
                length == null ? -1 : Long.parseLong(length),
                encoding != null && encoding.toLowerCase().contains("chunked"),
                parts));
            byte[] response = "{\"data\":{\"uploadOneFile\":true,\"uploadFileList\":true}}".getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(200, response.length);
            exchange.getResponseBody().write(response);
            exchange.close();
        });
        server.start();
    }

    public String url() { return "http://127.0.0.1:" + server.getAddress().getPort() + "/graphql"; }

    public Received only() {
        if (requests.size() != 1) throw new AssertionError("expected one request, got " + requests.size());
        return requests.get(0);
    }

    @Override
    public void close() { server.stop(0); }

    private static List<Part> parse(byte[] body, String boundary) {
        byte[] delimiter = ("--" + boundary).getBytes(StandardCharsets.UTF_8);
        byte[] headEnd = "\r\n\r\n".getBytes(StandardCharsets.UTF_8);
        List<Integer> starts = new ArrayList<>();
        for (int at = indexOf(body, delimiter, 0); at >= 0; at = indexOf(body, delimiter, at + delimiter.length)) starts.add(at);
        List<Part> parts = new ArrayList<>();
        Pattern disposition = Pattern.compile("name=\"([^\"]*)\"(?:; filename=\"([^\"]*)\")?");
        Pattern type = Pattern.compile("(?i)content-type: ([^\\r\\n]+)");
        for (int i = 0; i < starts.size() - 1; i++) {
            int from = starts.get(i) + delimiter.length + 2;
            int to = starts.get(i + 1) - 2;
            int headerEnd = indexOf(body, headEnd, from);
            String headers = new String(body, from, headerEnd - from, StandardCharsets.UTF_8);
            Matcher d = disposition.matcher(headers);
            d.find();
            Matcher t = type.matcher(headers);
            ByteArrayOutputStream bytes = new ByteArrayOutputStream();
            bytes.write(body, headerEnd + 4, to - (headerEnd + 4));
            parts.add(new Part(d.group(1), d.group(2), t.find() ? t.group(1) : null, bytes.toByteArray()));
        }
        return parts;
    }

    private static int indexOf(byte[] haystack, byte[] needle, int start) {
        outer:
        for (int i = start; i <= haystack.length - needle.length; i++) {
            for (int j = 0; j < needle.length; j++) if (haystack[i + j] != needle[j]) continue outer;
            return i;
        }
        return -1;
    }

    public static final class Sha {
        public static String of(byte[] bytes) {
            try {
                return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
            } catch (Exception e) {
                throw new RuntimeException(e);
            }
        }
    }
}
