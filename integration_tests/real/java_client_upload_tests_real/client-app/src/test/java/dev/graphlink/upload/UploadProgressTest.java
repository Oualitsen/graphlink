package dev.graphlink.upload;

import dev.graphlink.upload.generated.client.GLUpload;
import dev.graphlink.upload.generated.client.GraphLinkClient;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import static org.junit.jupiter.api.Assertions.*;

class UploadProgressTest {

    private RecordingServer server;
    private GraphLinkClient client;

    @BeforeEach
    void start() throws Exception {
        server = new RecordingServer();
        client = new GraphLinkClient(server.url());
    }

    @AfterEach
    void stop() { server.close(); }

    private static byte[] pattern(int size) {
        byte[] bytes = new byte[size];
        for (int i = 0; i < size; i++) bytes[i] = (byte) ((i * 31 + 7) % 251);
        return bytes;
    }

    private static GLUpload fileOf(byte[] bytes, String name, boolean knownLength) {
        return new GLUpload(new ByteArrayInputStream(bytes), knownLength ? bytes.length : -1, name);
    }

    @Test
    void sixMegabytesArriveIntactWithoutProgress() throws Exception {
        byte[] bytes = pattern(6 * 1024 * 1024);
        assertTrue(client.mutations.uploadOneFile("u1", fileOf(bytes, "big.bin", true)).getUploadOneFile());
        RecordingServer.Received sent = server.only();
        assertEquals(RecordingServer.Sha.of(bytes), sent.part("0").sha256());
        assertEquals("big.bin", sent.part("0").filename());
        assertTrue(sent.part("operations").text().contains("\"userId\":\"u1\""));
    }

    @Test
    void aFileOfKnownLengthIsSentWithAContentLength() throws Exception {
        byte[] bytes = pattern(300000);
        client.mutations.uploadOneFile("u1", fileOf(bytes, "a.bin", true));
        RecordingServer.Received sent = server.only();
        assertFalse(sent.chunked());
        assertTrue(sent.contentLength() > bytes.length);
    }

    @Test
    void aFileOfUnknownLengthArrivesIntactSentChunked() throws Exception {
        byte[] bytes = pattern(300000);
        client.mutations.uploadOneFile("u1", fileOf(bytes, "a.bin", false));
        RecordingServer.Received sent = server.only();
        assertEquals(RecordingServer.Sha.of(bytes), sent.part("0").sha256());
        assertTrue(sent.chunked());
    }

    @Test
    void sixMegabytesArriveIntactWithProgress() throws Exception {
        byte[] bytes = pattern(6 * 1024 * 1024);
        client.mutations.uploadOneFile("u1", fileOf(bytes, "big.bin", true), (sent, total) -> {});
        assertEquals(RecordingServer.Sha.of(bytes), server.only().part("0").sha256());
    }

    @Test
    void progressIncreasesAndEndsAtTheTotal() throws Exception {
        byte[] bytes = pattern(6 * 1024 * 1024);
        List<long[]> reports = new ArrayList<>();
        client.mutations.uploadOneFile("u1", fileOf(bytes, "big.bin", true), (sent, total) -> reports.add(new long[] {sent, total}));
        assertTrue(reports.size() > 10);
        for (int i = 1; i < reports.size(); i++) assertTrue(reports.get(i)[0] >= reports.get(i - 1)[0]);
        long[] last = reports.get(reports.size() - 1);
        assertEquals(last[1], last[0]);
        assertTrue(last[1] > bytes.length);
        assertEquals(server.only().contentLength(), last[1]);
    }

    @Test
    void theFileIsNotReadInFullBeforeTheFirstProgressReport() throws Exception {
        byte[] bytes = pattern(6 * 1024 * 1024);
        AtomicLong pulled = new AtomicLong();
        AtomicLong pulledAtFirstReport = new AtomicLong(-1);
        InputStream slow = new InputStream() {
            private int position;

            @Override
            public int read() { throw new UnsupportedOperationException(); }

            @Override
            public int read(byte[] buffer, int offset, int count) {
                if (position >= bytes.length) return -1;
                int read = Math.min(Math.min(count, 65536), bytes.length - position);
                System.arraycopy(bytes, position, buffer, offset, read);
                position += read;
                pulled.addAndGet(read);
                if (position % (256 * 1024) == 0) {
                    try { Thread.sleep(2); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
                }
                return read;
            }
        };
        client.mutations.uploadOneFile("u1", new GLUpload(slow, bytes.length, "big.bin"),
            (sent, total) -> pulledAtFirstReport.compareAndSet(-1, pulled.get()));
        assertTrue(pulledAtFirstReport.get() >= 0 && pulledAtFirstReport.get() < bytes.length,
            "progress path read " + pulledAtFirstReport.get() + " of " + bytes.length + " bytes before the first report");
    }

    @Test
    void aFileOfUnknownLengthFiresNoProgressAndArrivesIntact() throws Exception {
        byte[] bytes = pattern(300000);
        AtomicInteger calls = new AtomicInteger();
        client.mutations.uploadOneFile("u1", fileOf(bytes, "a.bin", false), (sent, total) -> calls.incrementAndGet());
        RecordingServer.Received sent = server.only();
        assertEquals(RecordingServer.Sha.of(bytes), sent.part("0").sha256());
        assertTrue(sent.chunked());
        assertEquals(0, calls.get());
    }

    @Test
    void twoFilesArriveIntactInSlotOrderWithProgress() throws Exception {
        byte[] a = pattern(1200000);
        byte[] b = pattern(900000);
        for (int i = 0; i < b.length / 2; i++) { byte t = b[i]; b[i] = b[b.length - 1 - i]; b[b.length - 1 - i] = t; }
        List<long[]> reports = new ArrayList<>();
        assertTrue(client.mutations.uploadFileList("u1", List.of(fileOf(a, "a.bin", true), fileOf(b, "b.bin", true)),
            (sent, total) -> reports.add(new long[] {sent, total})).getUploadFileList());
        RecordingServer.Received sent = server.only();
        assertEquals(RecordingServer.Sha.of(a), sent.part("0").sha256());
        assertEquals("a.bin", sent.part("0").filename());
        assertEquals(RecordingServer.Sha.of(b), sent.part("1").sha256());
        assertEquals("b.bin", sent.part("1").filename());
        long[] last = reports.get(reports.size() - 1);
        assertEquals(last[1], last[0]);
    }
}
