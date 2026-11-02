package dev.graphlink.rest

import dev.graphlink.rest.generated.client.*
import dev.graphlink.rest.generated.inputs.*
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class UploadsTest {
    private lateinit var client: GraphLinkClient

    @BeforeEach
    fun setUp() {
        resetServer()
        client = newClient()
    }

    @Test
    fun multipartHasABoundaryAndTextPartsWithoutFilename() = runBlocking {
        val e = client.mutations.eMultipart(title = "Hello é")
        assertTrue(Regex("^multipart/form-data; boundary=").containsMatchIn(e.contentType!!))
        val title = e.part("title")
        assertNull(title.filename)
        assertEquals("Hello é", title.text)
    }

    @Test
    fun fileParts() = runBlocking {
        val bytes = pattern(70000)
        val e = client.mutations.eMultipart(one = uploadOf(bytes, filename = "photo.png", mimeType = "image/png"))
        val part = e.part("one")
        assertEquals("photo.png", part.filename)
        assertTrue(part.contentType!!.startsWith("image/png"))
        assertEquals(bytes.size, part.size)
        assertEquals(sha256Of(bytes), part.sha256)
    }

    @Test
    fun listOfUploadsRepeatsThePartNameInOrder() = runBlocking {
        val files = listOf(pattern(10), pattern(2000), ByteArray(0))
        val e = client.mutations.eMultipart(many = files.mapIndexed { i, f -> uploadOf(f, filename = "f$i.bin") })
        val parts = e.partsNamed("many")
        assertEquals(listOf("f0.bin", "f1.bin", "f2.bin"), parts.map { it.filename })
        assertEquals(listOf(10, 2000, 0), parts.map { it.size })
        assertEquals(files.map { sha256Of(it) }, parts.map { it.sha256 })
    }

    @Test
    fun unknownLengthAndNonAsciiFilename() = runBlocking {
        val bytes = pattern(300000)
        assertEquals(sha256Of(bytes), client.mutations.eMultipart(one = uploadOf(bytes, "u.bin", knownLength = false)).part("one").sha256)
        val name = client.mutations.eMultipart(one = uploadOf(pattern(3), "é漢.png")).part("one").filename
        assertTrue(name == "é漢.png" || name == restEncode("é漢.png"))
    }

    @Test
    fun objectAndJsonParts() = runBlocking {
        val e = client.mutations.eMultipart(meta = Meta(name = "m", tags = listOf("a", "b"), address = Address(city = "Oran")))
        assertEquals("m", e.part("meta.name").text)
        assertEquals(listOf("a", "b"), e.partsNamed("meta.tags").map { it.text })
        assertEquals("Oran", e.part("meta.address.city").text)
        val json = client.mutations.eMultipart(asJson = Meta(name = "m")).part("j")
        assertTrue(json.contentType!!.startsWith("application/json"))
        assertEquals("m", (parseJson(json.text!!) as Map<*, *>)["name"])
    }

    @Test
    fun partsTravelTogetherAndNothingMeansNoBody() = runBlocking {
        val bytes = pattern(1000)
        val e = client.mutations.eMultipart(
            title = "t",
            asJson = Meta(name = "m"),
            one = uploadOf(bytes, "a.bin"),
            many = listOf(uploadOf(bytes, "b.bin"), uploadOf(bytes, "c.bin")),
        )
        assertEquals(listOf("title", "j", "one", "many", "many"), e.parts.map { it.name })
        val empty = client.mutations.eMultipart()
        assertEquals(0, empty.bodySize)
        assertNull(empty.contentType)
    }

    @Test
    fun multipartProgressEndsAtTheTotal() = runBlocking {
        val bytes = pattern(1500000)
        val reports = mutableListOf<LongArray>()
        val e = client.mutations.eMultipart(
            one = uploadOf(bytes, "big.bin"),
            onProgress = UploadProgressCallback { sent, total -> reports.add(longArrayOf(sent, total)) },
        )
        assertEquals(sha256Of(bytes), e.part("one").sha256)
        assertTrue(reports.isNotEmpty())
        for (i in 1 until reports.size) assertTrue(reports[i][0] >= reports[i - 1][0])
        assertEquals(reports.last()[1], reports.last()[0])
        assertTrue(reports.last()[1] > bytes.size)
    }

    @Test
    fun rawBodyIsExactlyTheFileBytes() = runBlocking {
        val bytes = pattern(120000)
        val e = client.mutations.eRaw(file = uploadOf(bytes, mimeType = "image/png"))
        assertEquals("PUT", e.method)
        assertTrue(e.contentType!!.startsWith("image/png"))
        assertEquals(bytes.size, e.bodySize)
        assertEquals(sha256Of(bytes), e.bodySha256)
        assertEquals(bytes.size, e.contentLength)
        assertFalse(e.chunked)
    }

    @Test
    fun unknownLengthRawUploadIsChunked() = runBlocking {
        val bytes = pattern(250000)
        val e = client.mutations.eRaw(file = uploadOf(bytes, knownLength = false))
        assertTrue(e.chunked)
        assertNull(e.contentLength)
        assertEquals(sha256Of(bytes), e.bodySha256)
    }

    @Test
    fun rawMimeTypeAndOptionalBodies() = runBlocking {
        assertTrue(client.mutations.eRaw(file = uploadOf(pattern(5))).contentType!!.startsWith("application/octet-stream"))
        assertTrue(client.mutations.eRawType(file = uploadOf(pattern(5), mimeType = "image/png")).contentType!!.startsWith("application/x-custom"))
        assertEquals(0, client.mutations.eRaw(file = uploadOf(ByteArray(0))).bodySize)
        val none = client.mutations.eRawOptional()
        assertEquals(0, none.bodySize)
        assertNull(none.contentType)
    }

    @Test
    fun filenameIsNotSentOnRawUploads() = runBlocking {
        val e = client.mutations.eRaw(file = uploadOf(pattern(5), filename = "secret-name.bin"))
        assertFalse(e.headers.joinToString("|") { it.value }.contains("secret-name"))
        assertFalse(e.path.contains("secret-name"))
    }

    @Test
    fun largeRawUploadProgress() = runBlocking {
        val bytes = pattern(6 * 1024 * 1024)
        val reports = mutableListOf<LongArray>()
        val e = client.mutations.eRaw(file = uploadOf(bytes), onProgress = UploadProgressCallback { s, t -> reports.add(longArrayOf(s, t)) })
        assertEquals(sha256Of(bytes), e.bodySha256)
        assertEquals(listOf(bytes.size.toLong(), bytes.size.toLong()), reports.last().toList())
        for (i in 1 until reports.size) assertTrue(reports[i][0] >= reports[i - 1][0])
        val unknown = mutableListOf<LongArray>()
        client.mutations.eRaw(file = uploadOf(pattern(40000), knownLength = false), onProgress = UploadProgressCallback { s, t -> unknown.add(longArrayOf(s, t)) })
        assertTrue(unknown.isNotEmpty())
        assertTrue(unknown.all { it[1] == -1L || it[1] == 40000L })
        assertEquals(40000L, unknown.last()[0])
    }

    @Test
    fun aFailingSourceFailsTheCallWithoutHanging() = runBlocking {
        withTimeout(10000) {
            assertFailsWith<Exception> { client.mutations.eRaw(file = failingUpload()) }
        }
        assertEquals("GET", client.queries.eAccept().method)
    }
}
