package dev.graphlink.rest;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.graphlink.rest.generated.client.*;
import dev.graphlink.rest.generated.types.Echo;
import dev.graphlink.rest.generated.types.Pair;
import dev.graphlink.rest.generated.types.Part;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.security.MessageDigest;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;
import java.util.stream.Collectors;

final class Support {
    static final int PORT = Integer.parseInt(System.getProperty("rest.port", "9987"));
    static final String SERVER_URL = "http://127.0.0.1:" + PORT;
    static final java.util.concurrent.ExecutorService POOL = java.util.concurrent.Executors.newCachedThreadPool(r -> {
        Thread t = new Thread(r);
        t.setDaemon(true);
        return t;
    });
    static final ObjectMapper MAPPER = new ObjectMapper();
    static final JacksonGraphLinkJsonCodec CODEC = new JacksonGraphLinkJsonCodec();

    private Support() {}

    static GraphLinkClient newClient() {
        return newClient(SERVER_URL, () -> Collections.emptyMap(), new InMemoryGraphLinkCacheStore());
    }

    static GraphLinkClient newClient(String baseUrl) {
        return newClient(baseUrl, () -> Collections.emptyMap(), new InMemoryGraphLinkCacheStore());
    }

    static GraphLinkClient newClient(GraphLinkCacheStore store) {
        return newClient(SERVER_URL, () -> Collections.emptyMap(), store);
    }

    static GraphLinkClient newClient(Supplier<Map<String, String>> headers) {
        return newClient(SERVER_URL, headers, new InMemoryGraphLinkCacheStore());
    }

    static GraphLinkClient newClient(String baseUrl, GraphLinkCacheStore store) {
        return newClient(baseUrl, () -> Collections.emptyMap(), store);
    }

    static GraphLinkClient newClient(String baseUrl, Supplier<Map<String, String>> headers, GraphLinkCacheStore store) {
        return new GraphLinkClient(
                new DefaultGraphLinkClientAdapter(baseUrl + "/graphql", headers),
                new DefaultGraphLinkRestAdapter(baseUrl, headers),
                CODEC,
                CODEC,
                store);
    }

    static void resetServer() throws IOException {
        HttpURLConnection connection = (HttpURLConnection) URI.create(SERVER_URL + "/_reset").toURL().openConnection();
        connection.setRequestMethod("POST");
        connection.getResponseCode();
        try (InputStream in = connection.getInputStream()) {
            in.readAllBytes();
        }
    }

    static List<String> pairs(List<Pair> list) {
        return list.stream().map(p -> p.getName() + "=" + p.getValue()).collect(Collectors.toList());
    }

    static List<String> queryPairs(Echo e) { return pairs(e.getQuery()); }

    static List<String> formPairs(Echo e) { return pairs(e.getForm()); }

    static String header(Echo e, String name) {
        return e.getHeaders().stream().filter(h -> h.getName().equals(name.toLowerCase())).map(Pair::getValue).findFirst().orElse(null);
    }

    static Part part(Echo e, String name) {
        return e.getParts().stream().filter(p -> p.getName().equals(name)).findFirst().orElseThrow();
    }

    static List<Part> partsNamed(Echo e, String name) {
        return e.getParts().stream().filter(p -> p.getName().equals(name)).collect(Collectors.toList());
    }

    static String queryValue(Echo e, String name) {
        return e.getQuery().stream().filter(p -> p.getName().equals(name)).map(Pair::getValue).findFirst().orElse(null);
    }

    static String formValue(Echo e, String name) {
        return e.getForm().stream().filter(p -> p.getName().equals(name)).map(Pair::getValue).findFirst().orElse(null);
    }

    static Object parseJson(String text) {
        try {
            return MAPPER.readValue(text, Object.class);
        } catch (IOException e) {
            throw new RuntimeException(e);
        }
    }

    static Object bodyJson(Echo e) { return parseJson(e.getBodyText()); }

    static byte[] pattern(int size) {
        byte[] data = new byte[size];
        for (int i = 0; i < size; i++) data[i] = (byte) (i % 251);
        return data;
    }

    static String sha256Of(byte[] bytes) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(bytes);
            StringBuilder out = new StringBuilder();
            for (byte b : digest) out.append(String.format("%02x", b));
            return out.toString();
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    static GLUpload uploadOf(byte[] bytes) { return uploadOf(bytes, null, "application/octet-stream", true); }

    static GLUpload uploadOf(byte[] bytes, String filename) { return uploadOf(bytes, filename, "application/octet-stream", true); }

    static GLUpload uploadOf(byte[] bytes, String filename, String mimeType, boolean knownLength) {
        return new GLUpload(new ByteArrayInputStream(bytes), knownLength ? bytes.length : -1L, filename, mimeType);
    }

    static GLUpload failingUpload() {
        InputStream stream = new InputStream() {
            private int sent = 0;

            @Override
            public int read() throws IOException {
                throw new UnsupportedOperationException();
            }

            @Override
            public int read(byte[] buffer, int offset, int length) throws IOException {
                if (sent >= 1000) throw new IOException("source failed");
                int count = Math.min(length, 1000 - sent);
                for (int i = 0; i < count; i++) buffer[offset + i] = 7;
                sent += count;
                return count;
            }
        };
        return new GLUpload(stream, -1L, null, "application/octet-stream");
    }
}
