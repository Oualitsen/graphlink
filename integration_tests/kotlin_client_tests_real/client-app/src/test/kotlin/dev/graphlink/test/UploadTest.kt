package dev.graphlink.test

import dev.graphlink.test.generated.client.GLUpload
import dev.graphlink.test.generated.client.GraphLinkClient
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import java.io.ByteArrayInputStream
import kotlin.test.assertTrue

class UploadTest {

    private lateinit var client: GraphLinkClient

    private fun makeFile(vararg bytes: Int, name: String = "test.png"): GLUpload {
        val data = ByteArray(bytes.size) { bytes[it].toByte() }
        return GLUpload(stream = ByteArrayInputStream(data), mimeType = "image/png",
                        length = data.size.toLong(), filename = name)
    }

    @BeforeEach fun setUp() { client = Fixtures.newUploadClient() }

    @Nested inner class UploadOneFile {
        @Test fun `returns true when file is provided`() = runTest {
            val res = client.mutations.uploadOneFile("user-1", makeFile(1, 2, 3))
            assertTrue(res.uploadOneFile)
        }
        @Test fun `returns true for a different userId`() = runTest {
            val res = client.mutations.uploadOneFile("user-42", makeFile(10, 20, 30))
            assertTrue(res.uploadOneFile)
        }
        @Test fun `returns true for a larger file`() = runTest {
            val res = client.mutations.uploadOneFile("user-1",
                GLUpload(stream = ByteArrayInputStream(ByteArray(1024) { (it % 256).toByte() }),
                         mimeType = "application/octet-stream", length = 1024, filename = "big.bin"))
            assertTrue(res.uploadOneFile)
        }
    }

    @Nested inner class UploadFileList {
        @Test fun `returns true for single file in list`() = runTest {
            val res = client.mutations.uploadFileList("user-1", listOf(makeFile(1, 2, 3)))
            assertTrue(res.uploadFileList)
        }
        @Test fun `returns true for two files`() = runTest {
            val res = client.mutations.uploadFileList("user-1",
                listOf(makeFile(1, 2, 3), makeFile(4, 5, 6, name = "second.png")))
            assertTrue(res.uploadFileList)
        }
        @Test fun `returns true for three files`() = runTest {
            val res = client.mutations.uploadFileList("user-2",
                listOf(makeFile(1), makeFile(2), makeFile(3)))
            assertTrue(res.uploadFileList)
        }
    }
}
