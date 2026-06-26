package dev.graphlink.test;

import dev.graphlink.test.generated.client.GLUpload;
import dev.graphlink.test.generated.client.GraphLinkMultipartAdapter;
import dev.graphlink.test.generated.client.UploadProgressCallback;
import reactor.core.publisher.Mono;

import java.io.*;
import java.net.URI;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.UUID;

public class RealMultipartAdapter implements GraphLinkMultipartAdapter {

    private final String url;
    private final HttpClient http = HttpClient.newHttpClient();

    public RealMultipartAdapter(String url) { this.url = url; }

    @Override
    public Mono<String> executeMultipart(String operations, String mapJson,
                                         Map<String, GLUpload> files,
                                         UploadProgressCallback onProgress) {
        return Mono.fromCallable(() -> {
            String boundary = UUID.randomUUID().toString();
            ByteArrayOutputStream body = new ByteArrayOutputStream();
            PrintWriter pw = new PrintWriter(new OutputStreamWriter(body, StandardCharsets.UTF_8), true);

            writePart(pw, body, boundary, "operations", operations.getBytes(StandardCharsets.UTF_8), "application/json", null);
            writePart(pw, body, boundary, "map",        mapJson.getBytes(StandardCharsets.UTF_8),   "application/json", null);
            for (Map.Entry<String, GLUpload> e : files.entrySet()) {
                GLUpload u = e.getValue();
                byte[] bytes = u.getStream().readAllBytes();
                writePart(pw, body, boundary, e.getKey(), bytes, u.getMimeType(),
                          u.getFilename() != null ? u.getFilename() : "upload");
            }
            pw.append("--").append(boundary).append("--\r\n");
            pw.flush();

            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .header("Content-Type", "multipart/form-data; boundary=" + boundary)
                    .POST(HttpRequest.BodyPublishers.ofByteArray(body.toByteArray()))
                    .build();
            try {
                return http.send(req, HttpResponse.BodyHandlers.ofString()).body();
            } catch (InterruptedException ex) {
                Thread.currentThread().interrupt();
                throw new IOException(ex);
            }
        });
    }

    private static void writePart(PrintWriter pw, OutputStream out, String boundary,
                                   String name, byte[] data, String contentType, String filename)
            throws IOException {
        pw.append("--").append(boundary).append("\r\n");
        if (filename != null) {
            pw.append("Content-Disposition: form-data; name=\"").append(name)
              .append("\"; filename=\"").append(filename).append("\"\r\n");
        } else {
            pw.append("Content-Disposition: form-data; name=\"").append(name).append("\"\r\n");
        }
        pw.append("Content-Type: ").append(contentType).append("\r\n\r\n");
        pw.flush();
        out.write(data);
        pw.append("\r\n");
        pw.flush();
    }
}
