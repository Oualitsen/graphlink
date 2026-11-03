package dev.graphlink.upload;

import dev.graphlink.upload.generated.client.GLUpload;
import dev.graphlink.upload.generated.client.GraphLinkClient;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

/** The generated adapter against the Spring Boot upload server, which the recording server cannot stand in for. */
class SpringServerUploadTest {

    private GraphLinkClient client;

    @BeforeEach
    void connect() {
        String url = System.getenv("UPLOAD_SERVER_URL");
        assumeTrue(url != null && !url.isEmpty(), "UPLOAD_SERVER_URL not set");
        client = new GraphLinkClient(url);
    }

    private static GLUpload fileOf(int size, boolean knownLength) {
        byte[] bytes = new byte[size];
        for (int i = 0; i < size; i++) bytes[i] = (byte) i;
        return new GLUpload(new ByteArrayInputStream(bytes), knownLength ? size : -1, "f.bin");
    }

    @Test
    void aFileOfKnownLengthIsAccepted() throws Exception {
        assertTrue(client.mutations.uploadOneFile("u1", fileOf(3_000_000, true), (s, t) -> {}).getUploadOneFile());
    }

    @Test
    void aFileOfUnknownLengthIsAcceptedChunked() throws Exception {
        assertTrue(client.mutations.uploadOneFile("u1", fileOf(3_000_000, false)).getUploadOneFile());
    }

    @Test
    void aListOfFilesIsAccepted() throws Exception {
        assertTrue(client.mutations.uploadFileList("u1", List.of(fileOf(1000, true), fileOf(2000, false))).getUploadFileList());
    }
}
