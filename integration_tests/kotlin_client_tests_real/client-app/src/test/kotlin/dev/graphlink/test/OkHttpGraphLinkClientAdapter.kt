package dev.graphlink.test

import dev.graphlink.test.generated.interfaces.GraphLinkClientAdapter
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

class OkHttpGraphLinkClientAdapter(private val url: String) : GraphLinkClientAdapter {

    private val client = OkHttpClient()

    override suspend fun execute(payload: String): String = withContext(Dispatchers.IO) {
        val body = payload.toRequestBody("application/json".toMediaType())
        val request = Request.Builder().url(url).post(body).build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("HTTP ${response.code}: ${response.message}")
            response.body!!.string()
        }
    }
}
