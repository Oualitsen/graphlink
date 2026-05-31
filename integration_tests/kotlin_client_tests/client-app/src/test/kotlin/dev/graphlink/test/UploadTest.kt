package dev.graphlink.test

import dev.graphlink.test.generated.client.GLUpload
import dev.graphlink.test.generated.client.GraphLinkClient
import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Nested
import kotlin.test.*
import dev.graphlink.test.Fixtures.kUserAliceJson
import dev.graphlink.test.Fixtures.newClientWithUpload

class UploadTest {

    private val codec = KotlinxSerializationGraphLinkJsonCodec()

    private lateinit var adapter: MockAdapter
    private lateinit var multipart: MockMultipartAdapter
    private lateinit var client: GraphLinkClient

    private fun makeFile(vararg bytes: Byte): GLUpload = GLUpload(
        stream = bytes.inputStream(),
        mimeType = "image/png",
        length = bytes.size.toLong(),
        filename = "test.png",
    )

    @BeforeTest
    fun setUp() {
        adapter = MockAdapter()
        multipart = MockMultipartAdapter()
        client = newClientWithUpload(adapter, MockWebSocketAdapter(), multipart)
    }

    // ── uploadOneFile ─────────────────────────────────────────────────────────

    @Nested
    inner class UploadOneFile {

        @BeforeTest
        fun register() {
            multipart.registerData("uploadOneFile", mapOf("uploadOneFile" to kUserAliceJson))
        }

        @Test
        fun response_id_isCorrect() = runTest {
            val res = client.mutations.uploadOneFile("user-1", makeFile(1, 2, 3))
            assertEquals("user-1", res.uploadOneFile.id)
        }

        @Test
        fun response_name_isCorrect() = runTest {
            val res = client.mutations.uploadOneFile("user-1", makeFile(1, 2, 3))
            assertEquals("Alice Smith", res.uploadOneFile.name)
        }

        @Test
        fun multipartAdapter_calledOnce() = runTest {
            client.mutations.uploadOneFile("user-1", makeFile(1, 2, 3))
            assertEquals(1, multipart.getCallCount())
        }

        @Test
        fun operations_containsCorrectUserId() = runTest {
            client.mutations.uploadOneFile("user-42", makeFile(1, 2, 3))
            val ops = codec.decode(multipart.getLastCall()!!.operations)
            @Suppress("UNCHECKED_CAST")
            val variables = ops["variables"] as Map<String, Any?>
            assertEquals("user-42", variables["userId"])
        }

        @Test
        fun fileVariable_isNull_inOperations() = runTest {
            client.mutations.uploadOneFile("user-1", makeFile(1, 2, 3))
            val ops = codec.decode(multipart.getLastCall()!!.operations)
            @Suppress("UNCHECKED_CAST")
            val variables = ops["variables"] as Map<String, Any?>
            assertNull(variables["file"])
        }

        @Test
        fun mapSlot0_pointsTo_variablesFile() = runTest {
            client.mutations.uploadOneFile("user-1", makeFile(1, 2, 3))
            val map = codec.decode(multipart.getLastCall()!!.mapJson)
            assertEquals(listOf("variables.file"), map["0"])
        }

        @Test
        fun filePart_presentUnderSlot0() = runTest {
            client.mutations.uploadOneFile("user-1", makeFile(1, 2, 3))
            assertTrue(multipart.getLastCall()!!.files.containsKey("0"))
        }

        @Test
        fun regularAdapter_notCalled() = runTest {
            client.mutations.uploadOneFile("user-1", makeFile(1, 2, 3))
            assertEquals(0, adapter.getCallCount())
        }
    }

    // ── uploadFileList ────────────────────────────────────────────────────────

    @Nested
    inner class UploadFileList {

        @BeforeTest
        fun register() {
            multipart.registerData("uploadFileList", mapOf("uploadFileList" to kUserAliceJson))
        }

        @Test
        fun response_id_isCorrect() = runTest {
            val res = client.mutations.uploadFileList("user-1", listOf(makeFile(1, 2, 3), makeFile(4, 5, 6)))
            assertEquals("user-1", res.uploadFileList.id)
        }

        @Test
        fun filesVariables_areAllNull_inOperations() = runTest {
            client.mutations.uploadFileList("user-1", listOf(makeFile(1, 2, 3), makeFile(4, 5, 6)))
            val ops = codec.decode(multipart.getLastCall()!!.operations)
            @Suppress("UNCHECKED_CAST")
            val variables = ops["variables"] as Map<String, Any?>
            val files = variables["files"] as List<*>
            assertEquals(2, files.size)
            assertNull(files[0])
            assertNull(files[1])
        }

        @Test
        fun mapSlot0_pointsTo_variablesFiles0() = runTest {
            client.mutations.uploadFileList("user-1", listOf(makeFile(1, 2, 3), makeFile(4, 5, 6)))
            val map = codec.decode(multipart.getLastCall()!!.mapJson)
            assertEquals(listOf("variables.files.0"), map["0"])
        }

        @Test
        fun mapSlot1_pointsTo_variablesFiles1() = runTest {
            client.mutations.uploadFileList("user-1", listOf(makeFile(1, 2, 3), makeFile(4, 5, 6)))
            val map = codec.decode(multipart.getLastCall()!!.mapJson)
            assertEquals(listOf("variables.files.1"), map["1"])
        }

        @Test
        fun bothFileParts_present() = runTest {
            client.mutations.uploadFileList("user-1", listOf(makeFile(1, 2, 3), makeFile(4, 5, 6)))
            val files = multipart.getLastCall()!!.files
            assertTrue(files.containsKey("0"))
            assertTrue(files.containsKey("1"))
        }

        @Test
        fun singleFileList_producesOneSlot() = runTest {
            client.mutations.uploadFileList("user-1", listOf(makeFile(1, 2, 3)))
            val map = codec.decode(multipart.getLastCall()!!.mapJson)
            assertEquals(1, map.size)
        }
    }
}
