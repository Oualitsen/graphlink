package dev.graphlink.test

import dev.graphlink.test.generated.client.GLUpload
import dev.graphlink.test.generated.client.GraphLinkMultipartAdapter
import dev.graphlink.test.generated.client.UploadProgressCallback
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody

class OkHttpMultipartAdapter(private val url: String) : GraphLinkMultipartAdapter {

    private val client = OkHttpClient()

    override suspend fun executeMultipart(
        operations: String,
        mapJson: String,
        files: Map<String, GLUpload>,
        onProgress: UploadProgressCallback?,
    ): String = withContext(Dispatchers.IO) {
        val builder = MultipartBody.Builder().setType(MultipartBody.FORM)
        builder.addFormDataPart("operations", operations)
        builder.addFormDataPart("map", mapJson)
        for ((key, upload) in files) {
            val bytes = upload.stream.readBytes()
            val body = bytes.toRequestBody(upload.mimeType.toMediaType())
            builder.addFormDataPart(key, upload.filename ?: "upload", body)
        }
        val request = Request.Builder().url(url).post(builder.build()).build()
        client.newCall(request).execute().use { it.body!!.string() }
    }
}
