package dev.graphlink.upload

import dev.graphlink.upload.generated.client.GLUpload
import dev.graphlink.upload.generated.client.GraphLinkClient
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class UploadProgressTest {
    private lateinit var server: RecordingServer
    private lateinit var client: GraphLinkClient

    @BeforeEach
    fun start() {
        server = RecordingServer()
        client = GraphLinkClient.create(server.url)
    }

    @AfterEach
    fun stop() = server.close()

    private fun pattern(size: Int) = ByteArray(size) { ((it * 31 + 7) % 251).toByte() }

    private fun fileOf(bytes: ByteArray, name: String, knownLength: Boolean) =
        GLUpload(ByteArrayInputStream(bytes), "application/octet-stream", if (knownLength) bytes.size.toLong() else -1L, name)

    @Test
    fun sixMegabytesArriveIntactWithoutProgress() = runBlocking {
        val bytes = pattern(6 * 1024 * 1024)
        assertTrue(client.mutations.uploadOneFile("u1", fileOf(bytes, "big.bin", true)).uploadOneFile)
        val sent = server.only()
        assertEquals(sha256Of(bytes), sent.part("0").sha256)
        assertEquals("big.bin", sent.part("0").filename)
        assertTrue(sent.part("operations").text.contains("\"userId\":\"u1\""))
    }

    @Test
    fun aFileOfKnownLengthIsSentWithAContentLength() = runBlocking {
        val bytes = pattern(300000)
        client.mutations.uploadOneFile("u1", fileOf(bytes, "a.bin", true))
        val sent = server.only()
        assertFalse(sent.chunked)
        assertTrue(sent.contentLength > bytes.size)
    }

    @Test
    fun aFileOfUnknownLengthArrivesIntactSentChunked() = runBlocking {
        val bytes = pattern(300000)
        client.mutations.uploadOneFile("u1", fileOf(bytes, "a.bin", false))
        val sent = server.only()
        assertEquals(sha256Of(bytes), sent.part("0").sha256)
        assertTrue(sent.chunked)
    }

    @Test
    fun sixMegabytesArriveIntactWithProgress() = runBlocking {
        val bytes = pattern(6 * 1024 * 1024)
        client.mutations.uploadOneFile("u1", fileOf(bytes, "big.bin", true)) { _, _ -> }
        assertEquals(sha256Of(bytes), server.only().part("0").sha256)
    }

    @Test
    fun progressIncreasesAndEndsAtTheTotal() = runBlocking {
        val bytes = pattern(6 * 1024 * 1024)
        val reports = mutableListOf<LongArray>()
        client.mutations.uploadOneFile("u1", fileOf(bytes, "big.bin", true)) { sent, total -> reports.add(longArrayOf(sent, total)) }
        assertTrue(reports.size > 10)
        for (i in 1 until reports.size) assertTrue(reports[i][0] >= reports[i - 1][0])
        val last = reports.last()
        assertEquals(last[1], last[0])
        assertTrue(last[1] > bytes.size)
        assertEquals(server.only().contentLength, last[1])
    }

    @Test
    fun theFileIsNotReadInFullBeforeTheFirstProgressReport() = runBlocking {
        val bytes = pattern(6 * 1024 * 1024)
        val pulled = AtomicLong()
        val pulledAtFirstReport = AtomicLong(-1)
        val slow = object : InputStream() {
            private var position = 0
            override fun read(): Int = throw UnsupportedOperationException()
            override fun read(buffer: ByteArray, offset: Int, count: Int): Int {
                if (position >= bytes.size) return -1
                val read = minOf(count, 65536, bytes.size - position)
                System.arraycopy(bytes, position, buffer, offset, read)
                position += read
                pulled.addAndGet(read.toLong())
                if (position % (256 * 1024) == 0) Thread.sleep(2)
                return read
            }
        }
        client.mutations.uploadOneFile("u1", GLUpload(slow, "application/octet-stream", bytes.size.toLong(), "big.bin")) { _, _ ->
            pulledAtFirstReport.compareAndSet(-1, pulled.get())
        }
        assertTrue(
            pulledAtFirstReport.get() in 0 until bytes.size,
            "progress path read ${pulledAtFirstReport.get()} of ${bytes.size} bytes before the first report",
        )
    }

    @Test
    fun aFileOfUnknownLengthFiresNoProgressAndArrivesIntact() = runBlocking {
        val bytes = pattern(300000)
        val calls = AtomicInteger()
        client.mutations.uploadOneFile("u1", fileOf(bytes, "a.bin", false)) { _, _ -> calls.incrementAndGet() }
        val sent = server.only()
        assertEquals(sha256Of(bytes), sent.part("0").sha256)
        assertTrue(sent.chunked)
        assertEquals(0, calls.get())
    }

    @Test
    fun twoFilesArriveIntactInSlotOrderWithProgress() = runBlocking {
        val a = pattern(1200000)
        val b = pattern(900000).reversedArray()
        val reports = mutableListOf<LongArray>()
        val response = client.mutations.uploadFileList("u1", listOf(fileOf(a, "a.bin", true), fileOf(b, "b.bin", true))) { sent, total ->
            reports.add(longArrayOf(sent, total))
        }
        assertTrue(response.uploadFileList)
        val sent = server.only()
        assertEquals(sha256Of(a), sent.part("0").sha256)
        assertEquals("a.bin", sent.part("0").filename)
        assertEquals(sha256Of(b), sent.part("1").sha256)
        assertEquals("b.bin", sent.part("1").filename)
        assertEquals(reports.last()[1], reports.last()[0])
    }
}
