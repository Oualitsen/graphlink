package dev.graphlink.rest

import dev.graphlink.rest.generated.client.*
import dev.graphlink.rest.generated.interfaces.*
import dev.graphlink.rest.generated.types.Echo
import dev.graphlink.rest.generated.types.Part
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URI
import java.security.MessageDigest

const val PORT = 9994
val serverUrl = "http://127.0.0.1:$PORT"

private val codec = KotlinxSerializationGraphLinkJsonCodec()

fun newClient(
    baseUrl: String = serverUrl,
    headers: (() -> Map<String, String>)? = null,
    store: GraphLinkCacheStore = InMemoryGraphLinkCacheStore(),
): GraphLinkClient {
    val adapter = DefaultGraphLinkClientAdapter("$baseUrl/graphql", headers)
    val rest = DefaultGraphLinkRestAdapter(baseUrl, headers)
    return GraphLinkClient(adapter, rest, codec, codec, store)
}

fun resetServer() {
    val connection = URI("$serverUrl/_reset").toURL().openConnection() as HttpURLConnection
    connection.requestMethod = "POST"
    connection.responseCode
    connection.inputStream.use { it.readBytes() }
}

fun Echo.queryPairs(): List<String> = query.map { "${it.name}=${it.value}" }
fun Echo.formPairs(): List<String> = form.map { "${it.name}=${it.value}" }
fun Echo.header(name: String): String? = headers.firstOrNull { it.name == name.lowercase() }?.value
fun Echo.part(name: String): Part = parts.first { it.name == name }
fun Echo.partsNamed(name: String): List<Part> = parts.filter { it.name == name }
fun Echo.queryValue(name: String): String? = query.firstOrNull { it.name == name }?.value
fun Echo.formValue(name: String): String? = form.firstOrNull { it.name == name }?.value
fun Echo.bodyJson(): Any? = parseJson(bodyText!!)

fun parseJson(text: String): Any? = codec.decode("{\"v\":$text}")["v"]

fun pattern(size: Int): ByteArray = ByteArray(size) { (it % 251).toByte() }

fun sha256Of(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

fun uploadOf(
    bytes: ByteArray,
    filename: String? = null,
    mimeType: String = "application/octet-stream",
    knownLength: Boolean = true,
): GLUpload = GLUpload(ByteArrayInputStream(bytes), mimeType, if (knownLength) bytes.size.toLong() else -1L, filename)

fun failingUpload(): GLUpload {
    val stream = object : InputStream() {
        private var sent = 0
        override fun read(): Int = throw UnsupportedOperationException()
        override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
            if (sent >= 1000) throw java.io.IOException("source failed")
            val count = minOf(length, 1000 - sent)
            for (i in 0 until count) buffer[offset + i] = 7
            sent += count
            return count
        }
    }
    return GLUpload(stream, "application/octet-stream", -1L, null)
}
