package dev.graphlink.test;

import dev.graphlink.test.generated.client.GLUpload;
import dev.graphlink.test.generated.client.GraphLinkClient;
import dev.graphlink.test.generated.types.UploadFileListResponse;
import dev.graphlink.test.generated.types.UploadOneFileResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.util.List;

import static dev.graphlink.test.Fixtures.newUploadClient;
import static org.junit.jupiter.api.Assertions.*;

class UploadTest {

    private GraphLinkClient client;

    private static GLUpload makeFile(int... ints) {
        byte[] bytes = new byte[ints.length];
        for (int i = 0; i < ints.length; i++) bytes[i] = (byte) ints[i];
        return new GLUpload(new ByteArrayInputStream(bytes), bytes.length, "test.png", "image/png");
    }

    @BeforeEach
    void setUp() { client = newUploadClient(); }

    @Nested
    class UploadOneFile {
        @Test void returns_true_when_file_provided() throws Exception {
            UploadOneFileResponse res = client.mutations.uploadOneFile("user-1", makeFile(1, 2, 3));
            assertTrue(res.getUploadOneFile());
        }
        @Test void returns_true_for_different_userId() throws Exception {
            UploadOneFileResponse res = client.mutations.uploadOneFile("user-42", makeFile(10, 20, 30));
            assertTrue(res.getUploadOneFile());
        }
        @Test void returns_true_for_larger_file() throws Exception {
            int[] ints = new int[1024];
            for (int i = 0; i < ints.length; i++) ints[i] = i % 256;
            UploadOneFileResponse res = client.mutations.uploadOneFile("user-1", makeFile(ints));
            assertTrue(res.getUploadOneFile());
        }
    }

    @Nested
    class UploadFileList {
        @Test void returns_true_for_single_file() throws Exception {
            UploadFileListResponse res = client.mutations.uploadFileList("user-1",
                    List.of(makeFile(1, 2, 3)));
            assertTrue(res.getUploadFileList());
        }
        @Test void returns_true_for_two_files() throws Exception {
            UploadFileListResponse res = client.mutations.uploadFileList("user-1",
                    List.of(makeFile(1, 2, 3), makeFile(4, 5, 6)));
            assertTrue(res.getUploadFileList());
        }
        @Test void returns_true_for_three_files() throws Exception {
            UploadFileListResponse res = client.mutations.uploadFileList("user-2",
                    List.of(makeFile(1), makeFile(2), makeFile(3)));
            assertTrue(res.getUploadFileList());
        }
    }
}
