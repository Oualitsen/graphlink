package dev.graphlink.upload

import dev.graphlink.upload.generated.client.GLUpload
import dev.graphlink.upload.generated.client.GraphLinkClient
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.io.ByteArrayInputStream
import kotlin.test.assertTrue

/** The generated adapter against the Spring Boot upload server, which the recording server cannot stand in for. */
class SpringServerUploadTest {
    private lateinit var client: GraphLinkClient

    @BeforeEach
    fun connect() {
        val url = System.getenv("UPLOAD_SERVER_URL")
        assumeTrue(!url.isNullOrEmpty(), "UPLOAD_SERVER_URL not set")
        client = GraphLinkClient.create(url)
    }

    private fun fileOf(size: Int, knownLength: Boolean) =
        GLUpload(ByteArrayInputStream(ByteArray(size) { it.toByte() }), "application/octet-stream", if (knownLength) size.toLong() else -1L, "f.bin")

    @Test
    fun aFileOfKnownLengthIsAccepted() = runBlocking {
        assertTrue(client.mutations.uploadOneFile("u1", fileOf(3_000_000, true)) { _, _ -> }.uploadOneFile)
    }

    @Test
    fun aFileOfUnknownLengthIsAcceptedChunked() = runBlocking {
        assertTrue(client.mutations.uploadOneFile("u1", fileOf(3_000_000, false)).uploadOneFile)
    }

    @Test
    fun aListOfFilesIsAccepted() = runBlocking {
        assertTrue(client.mutations.uploadFileList("u1", listOf(fileOf(1000, true), fileOf(2000, false))).uploadFileList)
    }
}
