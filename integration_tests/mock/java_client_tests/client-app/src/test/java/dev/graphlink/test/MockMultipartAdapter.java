package dev.graphlink.test;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.graphlink.test.generated.client.GLUpload;
import dev.graphlink.test.generated.client.GraphLinkMultipartAdapter;
import dev.graphlink.test.generated.client.UploadProgressCallback;

import java.io.IOException;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Drop-in multipart adapter for upload tests.
 *
 * Usage:
 *   MockMultipartAdapter multipart = new MockMultipartAdapter();
 *   multipart.registerData("uploadOneFile", Map.of("uploadOneFile", userJson));
 *   GraphLinkClient client = newClientWithUpload(adapter, multipart, wsAdapter);
 *   // ... call client methods ...
 *   assertEquals(1, multipart.getCallCount());
 *   assertNotNull(multipart.getLastCall().files().get("0"));
 */
public class MockMultipartAdapter implements GraphLinkMultipartAdapter {

    public record MultipartCall(
            String operations,
            String mapJson,
            Map<String, GLUpload> files
    ) {}

    private static final Pattern OPERATION_NAME_PATTERN =
            Pattern.compile("(?:query|mutation|subscription)\\s+(\\w+)");

    private static final ObjectMapper MAPPER = new ObjectMapper();

    private final Map<String, String> responses = new LinkedHashMap<>();
    private final List<MultipartCall> calls = new ArrayList<>();

    public void register(String operationName, String jsonResponse) {
        responses.put(operationName, jsonResponse);
    }

    public void registerData(String operationName, Map<String, Object> data) {
        try {
            register(operationName, MAPPER.writeValueAsString(Map.of("data", data)));
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    public List<MultipartCall> getCalls() {
        return Collections.unmodifiableList(calls);
    }

    public MultipartCall getLastCall() {
        return calls.isEmpty() ? null : calls.get(calls.size() - 1);
    }

    public int getCallCount() {
        return calls.size();
    }

    public void reset() {
        calls.clear();
        responses.clear();
    }

    @Override
    public String executeMultipart(String operations, String mapJson,
                                   Map<String, GLUpload> files,
                                   UploadProgressCallback onProgress) throws IOException {
        calls.add(new MultipartCall(operations, mapJson, new LinkedHashMap<>(files)));

        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> decoded = MAPPER.readValue(operations, Map.class);
            String query = (String) decoded.getOrDefault("query", "");
            String opName = extractOperationName(query);

            if (opName != null && responses.containsKey(opName)) {
                return responses.get(opName);
            }
            throw new IllegalStateException(
                    "MockMultipartAdapter: no response registered for \"" +
                    (opName != null ? opName : "unknown") + "\".\n" +
                    "Registered operations: " + responses.keySet()
            );
        } catch (RuntimeException e) {
            throw e;
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    private static String extractOperationName(String query) {
        Matcher m = OPERATION_NAME_PATTERN.matcher(query.trim());
        return m.find() ? m.group(1) : null;
    }
}
