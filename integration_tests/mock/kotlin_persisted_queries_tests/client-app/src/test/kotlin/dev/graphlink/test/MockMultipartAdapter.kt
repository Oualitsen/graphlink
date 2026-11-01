package dev.graphlink.test

import dev.graphlink.test.generated.client.GLUpload
import dev.graphlink.test.generated.client.GraphLinkMultipartAdapter
import dev.graphlink.test.generated.client.KotlinxSerializationGraphLinkJsonCodec
import dev.graphlink.test.generated.client.UploadProgressCallback

data class MultipartCall(
    val operationName: String?,
    val operations: String,
    val mapJson: String,
    val files: Map<String, GLUpload>,
)

class MockMultipartAdapter : GraphLinkMultipartAdapter {

    private val codec = KotlinxSerializationGraphLinkJsonCodec()
    private val responses = mutableMapOf<String, String>()
    private val _calls = mutableListOf<MultipartCall>()

    val calls: List<MultipartCall> get() = _calls
    fun getLastCall(): MultipartCall? = _calls.lastOrNull()
    fun getCallCount(): Int = _calls.size

    fun registerData(operationName: String, data: Map<String, Any?>) {
        responses[operationName] = codec.encode(mapOf("data" to data))
    }

    fun reset() {
        _calls.clear()
        responses.clear()
    }

    override suspend fun executeMultipart(
        operations: String,
        mapJson: String,
        files: Map<String, GLUpload>,
        onProgress: UploadProgressCallback?,
    ): String {
        val decoded = codec.decode(operations)
        val op = decoded["operationName"] as? String
        _calls += MultipartCall(op, operations, mapJson, files)
        return responses[op] ?: error(
            "MockMultipartAdapter: no response registered for \"$op\".\n" +
            "Registered operations: ${responses.keys}"
        )
    }
}
