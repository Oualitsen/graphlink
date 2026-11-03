package dev.graphlink.restmock;

import dev.graphlink.restmock.generated.client.RestBody;
import dev.graphlink.restmock.generated.client.RestRequest;
import dev.graphlink.restmock.generated.client.RestResponse;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;

abstract class MockRestCore {
    final List<RestRequest> calls = new ArrayList<>();
    final List<String> bodies = new ArrayList<>();
    boolean failTransport = false;
    private final Map<String, Supplier<RestResponse>> responses = new HashMap<>();

    void on(String method, String path, int status, String text, Map<String, String> headers) {
        responses.put(method + " " + path, () -> RestResponse.ofText(status, text, headers));
    }

    void on(String method, String path, String text) { on(method, path, 200, text, Collections.emptyMap()); }

    void on(String method, String path, int status) { on(method, path, status, "", Collections.emptyMap()); }

    void on(String method, String path, int status, String text) { on(method, path, status, text, Collections.emptyMap()); }

    RestRequest last() { return calls.get(calls.size() - 1); }

    RestResponse handle(RestRequest request) {
        if (failTransport) throw new IllegalStateException("offline");
        calls.add(request);
        RestBody body = request.getBody();
        try {
            if (body instanceof RestBody.Json json) bodies.add(json.getJson());
            else if (body instanceof RestBody.Raw raw) bodies.add(new String(raw.getUpload().getStream().readAllBytes(), StandardCharsets.UTF_8));
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        Supplier<RestResponse> response = responses.get(request.getMethod() + " " + request.getPath());
        return response != null ? response.get() : RestResponse.ofText(404, "no mock");
    }
}
