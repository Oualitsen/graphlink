package dev.graphlink.test;

import com.fasterxml.jackson.databind.ObjectMapper;
import dev.graphlink.test.generated.client.GLUpload;
import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.types.UploadFileListResponse;
import dev.graphlink.test.generated.types.UploadOneFileResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.List;
import java.util.Map;

import static dev.graphlink.test.Fixtures.*;
import static org.junit.jupiter.api.Assertions.*;

class UploadTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    private MockAdapter adapter;
    private MockMultipartAdapter multipart;
    private GraphLinkClient client;

    private static GLUpload makeFile(int... ints) {
        byte[] bytes = new byte[ints.length];
        for (int i = 0; i < ints.length; i++) bytes[i] = (byte) ints[i];
        return GLUpload.fromBytes(bytes, "test.png", "image/png");
    }

    @BeforeEach
    void setUp() {
        adapter = new MockAdapter();
        multipart = new MockMultipartAdapter();
        client = newClientWithUpload(adapter, multipart, new MockWebSocketAdapter());
    }

    // ── uploadOneFile ─────────────────────────────────────────────────────────

    @Nested
    class UploadOneFile {

        @BeforeEach
        void register() {
            multipart.registerData("uploadOneFile", Map.of("uploadOneFile", kUserAliceJson));
        }

        @Test
        void response_id_isCorrect() throws Exception {
            UploadOneFileResponse res = client.mutations.uploadOneFile("user-1", makeFile(1, 2, 3));
            assertEquals("user-1", res.getUploadOneFile().getId());
        }

        @Test
        void response_name_isCorrect() throws Exception {
            UploadOneFileResponse res = client.mutations.uploadOneFile("user-1", makeFile(1, 2, 3));
            assertEquals("Alice Smith", res.getUploadOneFile().getName());
        }

        @Test
        void multipartAdapter_calledOnce() throws Exception {
            client.mutations.uploadOneFile("user-1", makeFile(1, 2, 3));
            assertEquals(1, multipart.getCallCount());
        }

        @Test
        void operations_containsCorrectUserId() throws Exception {
            client.mutations.uploadOneFile("user-42", makeFile(1, 2, 3));
            @SuppressWarnings("unchecked")
            Map<String, Object> ops = MAPPER.readValue(multipart.getLastCall().operations(), Map.class);
            @SuppressWarnings("unchecked")
            Map<String, Object> variables = (Map<String, Object>) ops.get("variables");
            assertEquals("user-42", variables.get("userId"));
        }

        @Test
        void fileVariable_isNull_inOperations() throws Exception {
            client.mutations.uploadOneFile("user-1", makeFile(1, 2, 3));
            @SuppressWarnings("unchecked")
            Map<String, Object> ops = MAPPER.readValue(multipart.getLastCall().operations(), Map.class);
            @SuppressWarnings("unchecked")
            Map<String, Object> variables = (Map<String, Object>) ops.get("variables");
            assertNull(variables.get("file"));
        }

        @Test
        void mapSlot0_pointsTo_variablesFile() throws Exception {
            client.mutations.uploadOneFile("user-1", makeFile(1, 2, 3));
            @SuppressWarnings("unchecked")
            Map<String, Object> map = MAPPER.readValue(multipart.getLastCall().mapJson(), Map.class);
            assertEquals(List.of("variables.file"), map.get("0"));
        }

        @Test
        void filePart_presentUnderSlot0() throws Exception {
            client.mutations.uploadOneFile("user-1", makeFile(1, 2, 3));
            assertTrue(multipart.getLastCall().files().containsKey("0"));
        }

        @Test
        void regularAdapter_notCalled() throws Exception {
            client.mutations.uploadOneFile("user-1", makeFile(1, 2, 3));
            assertEquals(0, adapter.getCallCount());
        }
    }

    // ── uploadFileList ────────────────────────────────────────────────────────

    @Nested
    class UploadFileList {

        @BeforeEach
        void register() {
            multipart.registerData("uploadFileList", Map.of("uploadFileList", kUserAliceJson));
        }

        @Test
        void response_id_isCorrect() throws Exception {
            UploadFileListResponse res = client.mutations.uploadFileList(
                    "user-1", List.of(makeFile(1, 2, 3), makeFile(4, 5, 6)));
            assertEquals("user-1", res.getUploadFileList().getId());
        }

        @Test
        void filesVariables_areAllNull_inOperations() throws Exception {
            client.mutations.uploadFileList(
                    "user-1", List.of(makeFile(1, 2, 3), makeFile(4, 5, 6)));
            @SuppressWarnings("unchecked")
            Map<String, Object> ops = MAPPER.readValue(multipart.getLastCall().operations(), Map.class);
            @SuppressWarnings("unchecked")
            Map<String, Object> variables = (Map<String, Object>) ops.get("variables");
            assertEquals(Arrays.asList(null, null), variables.get("files"));
        }

        @Test
        void mapSlot0_pointsTo_variablesFiles0() throws Exception {
            client.mutations.uploadFileList(
                    "user-1", List.of(makeFile(1, 2, 3), makeFile(4, 5, 6)));
            @SuppressWarnings("unchecked")
            Map<String, Object> map = MAPPER.readValue(multipart.getLastCall().mapJson(), Map.class);
            assertEquals(List.of("variables.files.0"), map.get("0"));
        }

        @Test
        void mapSlot1_pointsTo_variablesFiles1() throws Exception {
            client.mutations.uploadFileList(
                    "user-1", List.of(makeFile(1, 2, 3), makeFile(4, 5, 6)));
            @SuppressWarnings("unchecked")
            Map<String, Object> map = MAPPER.readValue(multipart.getLastCall().mapJson(), Map.class);
            assertEquals(List.of("variables.files.1"), map.get("1"));
        }

        @Test
        void bothFileParts_present() throws Exception {
            client.mutations.uploadFileList(
                    "user-1", List.of(makeFile(1, 2, 3), makeFile(4, 5, 6)));
            Map<String, ?> files = multipart.getLastCall().files();
            assertTrue(files.containsKey("0"));
            assertTrue(files.containsKey("1"));
        }

        @Test
        void singleFileList_producesOneSlot() throws Exception {
            client.mutations.uploadFileList("user-1", List.of(makeFile(1, 2, 3)));
            @SuppressWarnings("unchecked")
            Map<String, Object> map = MAPPER.readValue(multipart.getLastCall().mapJson(), Map.class);
            assertEquals(1, map.size());
        }
    }
}
