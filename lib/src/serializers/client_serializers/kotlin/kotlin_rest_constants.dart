const kotlinRestFile = r'''
import java.io.ByteArrayInputStream
import java.io.Closeable
import java.io.InputStream

fun interface GLRestAdapter {
    suspend fun execute(request: RestRequest): RestResponse
}

fun interface DownloadProgressCallback {
    fun onProgress(received: Long, total: Long)
}

sealed class RestBody

class RestJsonBody(val json: String) : RestBody()

class RestFormBody(val fields: List<Pair<String, String>>) : RestBody()

class RestPart private constructor(
    val name: String,
    val value: String?,
    val file: GLUpload?,
    val mimeType: String?,
) {
    companion object {
        fun text(name: String, value: String, mimeType: String? = null) = RestPart(name, value, null, mimeType)
        fun file(name: String, file: GLUpload) = RestPart(name, null, file, null)
    }
}

class RestMultipartBody(val parts: List<RestPart>) : RestBody()

class RestRawBody(val upload: GLUpload) : RestBody()

class RestRequest(
    val method: String,
    val path: String,
    val query: List<Pair<String, String>> = emptyList(),
    val headers: Map<String, String> = emptyMap(),
    val body: RestBody? = null,
    val onSendProgress: UploadProgressCallback? = null,
)

class RestResponse(
    val status: Int,
    val stream: InputStream,
    val headers: Map<String, String> = emptyMap(),
) : Closeable {
    val isSuccess: Boolean get() = status in 200..299

    fun bytes(): ByteArray = stream.use { it.readBytes() }

    fun text(): String = String(bytes(), Charsets.UTF_8).removePrefix(Char(0xFEFF).toString())

    fun drain() {
        stream.use { it.copyTo(java.io.OutputStream.nullOutputStream()) }
    }

    override fun close() = stream.close()

    companion object {
        fun ofText(status: Int, text: String, headers: Map<String, String> = emptyMap()) =
            RestResponse(status, ByteArrayInputStream(text.toByteArray(Charsets.UTF_8)), headers)
    }
}

class RestError(
    val status: Int,
    val headers: Map<String, String>,
    val body: String,
) : Exception("RestError($status): $body")

class GLDownload(
    val stream: InputStream,
    val filename: String? = null,
    val contentType: String? = null,
    val length: Long? = null,
) : Closeable {
    fun bytes(): ByteArray = stream.use { it.readBytes() }

    override fun close() = stream.close()

    companion object {
        private val filenamePattern = Regex("filename\\*?=(?:UTF-8'')?\"?([^\";]+)\"?", RegexOption.IGNORE_CASE)

        fun fromResponse(response: RestResponse, onProgress: DownloadProgressCallback? = null): GLDownload {
            fun header(name: String): String? = response.headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value
            val length = header("content-length")?.toLongOrNull()
            val stream = if (onProgress == null) response.stream else CountingInputStream(response.stream, length ?: -1L, onProgress)
            val name = header("content-disposition")?.let { filenamePattern.find(it)?.groupValues?.get(1) }
                ?.let { runCatching { java.net.URLDecoder.decode(it.replace("+", "%2B"), "UTF-8") }.getOrDefault(it) }
            return GLDownload(stream, name, header("content-type"), length)
        }
    }
}

private class CountingInputStream(
    private val delegate: InputStream,
    private val total: Long,
    private val callback: DownloadProgressCallback,
) : InputStream() {
    private var received = 0L

    override fun read(): Int {
        val value = delegate.read()
        if (value >= 0) report(1)
        return value
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        val count = delegate.read(buffer, offset, length)
        if (count > 0) report(count.toLong())
        return count
    }

    override fun close() = delegate.close()

    private fun report(count: Long) {
        received += count
        callback.onProgress(received, total)
    }
}

fun restEncode(value: String): String {
    val out = StringBuilder()
    for (byte in value.toByteArray(Charsets.UTF_8)) {
        val c = byte.toInt() and 0xFF
        val unreserved = (c in 'a'.code..'z'.code) || (c in 'A'.code..'Z'.code) || (c in '0'.code..'9'.code) ||
            c == '-'.code || c == '_'.code || c == '.'.code || c == '~'.code
        if (unreserved) out.append(c.toChar()) else out.append('%').append("%02X".format(c))
    }
    return out.toString()
}

fun restEncodeQuery(value: String): String = restEncode(value).replace("%20", "+")

private fun restText(value: Any): String = if (value is String) value else value.toString()

private fun restCollect(
    out: MutableList<Pair<String, String>>,
    key: String,
    value: Any?,
    bracket: Boolean,
    comma: Boolean,
    inList: Boolean,
) {
    when (value) {
        null -> return
        is Map<*, *> -> value.forEach { (k, v) -> restCollect(out, if (bracket) "$key[$k]" else "$key.$k", v, bracket, comma, false) }
        is List<*> -> {
            val items = value.filterNotNull()
            if (items.isEmpty()) return
            if (!inList && items.all { it !is Map<*, *> && it !is List<*> }) {
                if (comma) out.add(key to items.joinToString(",") { restText(it) })
                else items.forEach { out.add(key to restText(it)) }
            } else {
                value.forEachIndexed { i, e -> restCollect(out, if (bracket) "$key[$i]" else "$key.$i", e, bracket, comma, true) }
            }
        }
        else -> out.add(key to restText(value))
    }
}

fun restEntries(key: String, value: Any?, bracket: Boolean = false, comma: Boolean = false): List<Pair<String, String>> {
    val out = mutableListOf<Pair<String, String>>()
    restCollect(out, key, value, bracket, comma, false)
    return out
}

fun restSpreadEntries(json: Any?, names: Map<String, String>, bracket: Boolean = false, comma: Boolean = false): List<Pair<String, String>> {
    val out = mutableListOf<Pair<String, String>>()
    if (json is Map<*, *>) names.forEach { (field, wire) -> restCollect(out, wire, json[field], bracket, comma, false) }
    return out
}

fun restHeaderValue(value: Any): String =
    if (value is List<*>) value.filterNotNull().joinToString(",") { restText(it) } else restText(value)

fun restHeader(name: String, value: Any?): Map<String, String> =
    if (value == null) emptyMap() else mapOf(name to restHeaderValue(value))

fun restHeaders(json: Any?, names: Map<String, String>): Map<String, String> {
    val out = mutableMapOf<String, String>()
    if (json is Map<*, *>) names.forEach { (field, header) -> json[field]?.let { out[header] = restHeaderValue(it) } }
    return out
}

fun restParts(entries: List<Pair<String, String>>): List<RestPart> = entries.map { RestPart.text(it.first, it.second) }

fun restNavigate(json: Any?, path: List<String>): Any? {
    var current = json
    for (segment in path) current = (current as? Map<*, *>)?.get(segment)
    return current
}
''';

String kotlinRestResolver({required bool withGetAdapter}) => '''
open class GraphLinkRestResolver(
    adapter: GraphLinkClientAdapter,
    fragmentMap: Map<String, String>,
    store: GraphLinkCacheStore,
    encoder: GraphLinkJsonEncoder,
    decoder: GraphLinkJsonDecoder,${withGetAdapter ? '\n    getAdapter: GraphLinkClientAdapter? = null,' : ''}
) : GraphLinkResolverBase(adapter, fragmentMap, store, encoder, decoder${withGetAdapter ? ', getAdapter' : ''}) {
    lateinit var restAdapter: GLRestAdapter

    protected suspend fun restCall(request: RestRequest): RestResponse {
        val response = restAdapter.execute(request)
        if (!response.isSuccess) {
            val error = RestError(response.status, response.headers, response.text())
            throw error
        }
        return response
    }

    protected suspend fun restVoid(request: RestRequest) {
        restCall(request).drain()
    }

    protected suspend fun restDownload(request: RestRequest, allowEmpty: Boolean, onProgress: DownloadProgressCallback?): GLDownload? {
        val response = restCall(request)
        if (response.status == 204) {
            response.drain()
            if (allowEmpty) return null
            throw IllegalStateException("Empty REST response for a non-null download of \${request.method} \${request.path}")
        }
        return GLDownload.fromResponse(response, onProgress)
    }

    protected suspend fun restText(request: RestRequest): String = restCall(request).text()

    protected suspend fun restTextOrNull(request: RestRequest): String? = restCall(request).text().ifEmpty { null }

    protected suspend fun restJson(request: RestRequest, path: List<String>, allowEmpty: Boolean): Any? {
        val text = restCall(request).text()
        val json = if (text.isBlank()) null else restNavigate(decoder.decode("{\\"v\\":\$text}")["v"], path)
        if (json == null && !allowEmpty) {
            throw IllegalStateException("Empty REST response for a non-null result of \${request.method} \${request.path}")
        }
        return json
    }

    protected fun restEncodeJson(value: Any?): String {
        val text = encoder.encode(mapOf("v" to value))
        return text.substring(text.indexOf(':') + 1, text.lastIndexOf('}')).trim()
    }

    protected suspend fun <T> restCached(
        name: String,
        variables: Map<String, Any?>,
        ttl: Long,
        tags: List<String>,
        staleIfOffline: Boolean,
        fetch: suspend () -> Any?,
        decode: (Any?) -> T,
    ): T {
        val key = GraphLinkPartialQuery.computeCacheKey(name, variables, encoder)
        val cached = getFromCache(key, tags, staleIfOffline)
        if (cached != null && !cached.stale) return decode(decoder.decode(cached.data)["__gl_v__"])
        val json: Any?
        try {
            json = fetch()
        } catch (e: RestError) {
            throw e
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            if (cached != null) return decode(decoder.decode(cached.data)["__gl_v__"])
            throw e
        }
        val value = decode(json)
        if (json != null) {
            val entry = GraphLinkCacheEntry(encoder.encode(mapOf("__gl_v__" to json)), System.currentTimeMillis() + ttl * 1000L)
            store.set(key, encoder.encode(entry.toJson()))
            if (tags.isNotEmpty()) addKeyToTags(key, tags)
        }
        return value
    }
}
''';

const kotlinRestOkHttpAdapter = r'''
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import okhttp3.Call
import kotlinx.coroutines.withContext
import okhttp3.Headers.Companion.toHeaders
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okio.BufferedSink
import okio.buffer
import okio.source

class DefaultGraphLinkRestAdapter(
    private val baseUrl: String,
    private val headersProvider: (() -> Map<String, String>)? = null,
    private val httpClient: OkHttpClient = OkHttpClient(),
) : GLRestAdapter {

    override suspend fun execute(request: RestRequest): RestResponse = withContext(Dispatchers.IO) {
        val headers = (headersProvider?.invoke() ?: emptyMap()) + request.headers
        val contentType = headers.entries.firstOrNull { it.key.equals("Content-Type", ignoreCase = true) }?.value
        val builder = Request.Builder()
            .url(url(request))
            .method(request.method, body(request, contentType))
        headers.filterKeys { !it.equals("Content-Type", ignoreCase = true) }.forEach { (k, v) -> builder.header(k, v) }
        val response = glCancellable(httpClient.newCall(builder.build())) { it.execute() }
        val responseHeaders = response.headers.toMultimap().mapValues { it.value.joinToString(",") }
        RestResponse(response.code, response.body!!.byteStream(), responseHeaders)
    }

    private fun url(request: RestRequest): String {
        val base = baseUrl.trimEnd('/')
        val query = request.query.joinToString("&") { "${restEncodeQuery(it.first)}=${restEncodeQuery(it.second)}" }
        return base + request.path + if (query.isEmpty()) "" else "?$query"
    }

    private fun body(request: RestRequest, contentType: String?): RequestBody? {
        val mediaType = contentType?.toMediaTypeOrNull()
        return when (val body = request.body) {
            null -> if (request.method == "GET" || request.method == "HEAD") null else ByteArray(0).toRequestBody(null)
            is RestJsonBody -> body.json.toRequestBody(mediaType)
            is RestFormBody -> body.fields.joinToString("&") { "${restEncodeQuery(it.first)}=${restEncodeQuery(it.second)}" }.toRequestBody(mediaType)
            is RestRawBody -> counted(rawBody(body.upload, mediaType), request.onSendProgress)
            is RestMultipartBody -> counted(multipart(body), request.onSendProgress)
        }
    }

    private fun rawBody(upload: GLUpload, mediaType: okhttp3.MediaType?): RequestBody = object : RequestBody() {
        override fun contentType() = mediaType
        override fun contentLength() = upload.length
        override fun isOneShot() = true
        override fun writeTo(sink: BufferedSink) {
            upload.stream.source().use { sink.writeAll(it) }
        }
    }

    private fun multipart(body: RestMultipartBody): RequestBody {
        val builder = MultipartBody.Builder().setType(MultipartBody.FORM)
        for (part in body.parts) {
            val file = part.file
            if (file == null) {
                builder.addPart(MultipartBody.Part.createFormData(part.name, null, part.value!!.toRequestBody(part.mimeType?.toMediaTypeOrNull())))
            } else {
                builder.addPart(MultipartBody.Part.createFormData(part.name, file.filename, rawBody(file, file.mimeType.toMediaTypeOrNull())))
            }
        }
        return builder.build()
    }

    private fun counted(delegate: RequestBody, callback: UploadProgressCallback?): RequestBody {
        if (callback == null || delegate.contentLength() <= 0) return delegate
        return object : RequestBody() {
            override fun contentType() = delegate.contentType()
            override fun contentLength() = delegate.contentLength()
            override fun isOneShot() = delegate.isOneShot()
            override fun writeTo(sink: BufferedSink) {
                val total = contentLength()
                var sent = 0L
                val counting = object : okio.ForwardingSink(sink) {
                    override fun write(source: okio.Buffer, byteCount: Long) {
                        super.write(source, byteCount)
                        sent += byteCount
                        callback.onProgress(sent, total)
                    }
                }
                val buffered = counting.buffer()
                delegate.writeTo(buffered)
                buffered.flush()
            }
        }
    }
}

private suspend fun <T> glCancellable(call: Call, block: (Call) -> T): T = coroutineScope {
    val finished = java.util.concurrent.atomic.AtomicBoolean(false)
    val watcher = launch(Dispatchers.Default) {
        try { awaitCancellation() } finally { if (!finished.get()) call.cancel() }
    }
    try {
        block(call)
    } catch (e: java.io.IOException) {
        currentCoroutineContext().ensureActive()
        throw e
    } finally {
        finished.set(true)
        watcher.cancel()
    }
}
''';

String kotlinNoGraphQLAdapter(bool withOperationName) => '''
object GraphLinkNoGraphQL : GraphLinkClientAdapter {
    override suspend fun execute(payload: String${withOperationName ? ', operationName: String' : ''}): String =
        throw IllegalStateException("This schema has no GraphQL operation: pass no GraphQL adapter")
}
''';
