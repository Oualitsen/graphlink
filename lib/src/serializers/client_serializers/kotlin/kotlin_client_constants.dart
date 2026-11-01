import 'package:graphlink/src/persisted_queries.dart';

const kotlinClientException = 'GraphLinkException';
const kotlinClientName = 'GraphLinkClient';

// ── Interfaces ────────────────────────────────────────────────────────────────

const kotlinGraphLinkClientAdapter = '''
fun interface GraphLinkClientAdapter {
    suspend fun execute(payload: String): String
}
''';

const kotlinGraphLinkClientAdapterWithOperationName = '''
fun interface GraphLinkClientAdapter {
    suspend fun execute(payload: String, operationName: String): String
}
''';

const kotlinGraphLinkJsonEncoder = '''
fun interface GraphLinkJsonEncoder {
    fun encode(payload: Map<String, Any?>): String
}
''';

const kotlinGraphLinkJsonDecoder = '''
fun interface GraphLinkJsonDecoder {
    fun decode(data: String): Map<String, Any?>
}
''';

const kotlinGraphLinkCacheStore = '''
interface GraphLinkCacheStore {
    fun set(key: String, value: String)
    fun get(key: String): String?
    fun invalidate(key: String)
    fun invalidateAll()
}
''';

const kotlinGraphLinkWebSocketAdapter = '''
interface GraphLinkWebSocketAdapter {
    fun connect(onConnect: () -> Unit, onFailure: (Throwable) -> Unit)
    fun sendMessage(message: String)
    fun close()
    fun setMessageListener(listener: (String) -> Unit)
    fun setReconnectListener(onReconnect: () -> Unit)
    fun connectionInitPayload(): Map<String, Any?>? = null
}
''';

const kotlinGraphLinkMultipartAdapter = '''
interface GraphLinkMultipartAdapter {
    suspend fun executeMultipart(
        operations: String,
        mapJson: String,
        files: Map<String, GLUpload>,
        onProgress: UploadProgressCallback?,
    ): String
}
''';

// ── Data classes ──────────────────────────────────────────────────────────────

const kotlinGraphLinkCacheEntry = '''
data class GraphLinkCacheEntry(
    val data: String,
    val expiry: Long,
    val stale: Boolean = false,
) {
    fun isExpired(): Boolean = System.currentTimeMillis() > expiry
    fun asStale(): GraphLinkCacheEntry = copy(stale = true)

    fun toJson(): Map<String, Any?> = mapOf("data" to data, "expiry" to expiry)

    companion object {
        fun fromJson(map: Map<String, Any?>): GraphLinkCacheEntry = GraphLinkCacheEntry(
            data = map["data"] as String,
            expiry = (map["expiry"] as Number).toLong(),
        )
    }
}
''';

const kotlinGraphLinkTagEntry = '''
data class GraphLinkTagEntry(val keys: MutableSet<String> = mutableSetOf()) {
    fun add(key: String) { keys.add(key) }
    fun remove(key: String) { keys.remove(key) }

    fun toJson(): Map<String, Any?> = mapOf("keys" to keys.toList())

    companion object {
        fun fromJson(map: Map<String, Any?>): GraphLinkTagEntry =
            GraphLinkTagEntry((map["keys"] as? List<*>)?.mapNotNull { it as? String }?.toMutableSet() ?: mutableSetOf())
    }
}
''';

const kotlinGraphLinkPartialQuery = '''
data class GraphLinkPartialQuery(
    val query: String,
    val variables: Map<String, Any?>,
    val ttl: Long,
    val tags: List<String>,
    val operationName: String,
    val elementKey: String,
    val fragmentNames: Set<String>,
    val argumentDeclarations: List<String>,
    val staleIfOffline: Boolean,
    val encoder: GraphLinkJsonEncoder,
) {
    val cacheKey: String by lazy { computeCacheKey(operationName, variables, encoder) }

    companion object {
        private fun computeCacheKey(operationName: String, variables: Map<String, Any?>, encoder: GraphLinkJsonEncoder): String {
            val raw = operationName + ":" + encoder.encode(java.util.TreeMap(variables))
            return fnv1a(raw)
        }

        private fun fnv1a(input: String): String {
            var hash = -0x3750b019380b25b8L
            for (b in input.toByteArray(Charsets.UTF_8)) {
                hash = hash xor (b.toLong() and 0xFF)
                hash *= 0x00000100000001B3L
            }
            return java.lang.Long.toUnsignedString(hash)
        }
    }
}
''';

const kotlinGraphlinkWsMessageTypes = '''
object GraphlinkWsMessageTypes {
    const val connectionInit = "connection_init"
    const val connectionAck = "connection_ack"
    const val subscribe = "subscribe"
    const val ping = "ping"
    const val pong = "pong"
    const val next = "next"
    const val error = "error"
    const val complete = "complete"
}
''';

const kotlinGraphLinkAckStatus = '''
enum class GraphLinkAckStatus { NONE, PROGRESS, ACKNOWLEDGED }
''';

// ── Codec ─────────────────────────────────────────────────────────────────────

const kotlinxSerializationCodec = '''
import kotlinx.serialization.json.*

class KotlinxSerializationGraphLinkJsonCodec : GraphLinkJsonEncoder, GraphLinkJsonDecoder {
    private val json = Json { ignoreUnknownKeys = true }

    override fun encode(payload: Map<String, Any?>): String =
        json.encodeToString(JsonElement.serializer(), payload.toJsonElement())

    override fun decode(data: String): Map<String, Any?> =
        json.parseToJsonElement(data).jsonObject.toAnyMap()
}

private fun Map<String, Any?>.toJsonElement(): JsonElement = buildJsonObject {
    forEach { (k, v) -> put(k, v.toJsonElement()) }
}

private fun Any?.toJsonElement(): JsonElement = when (this) {
    null -> JsonNull
    is Boolean -> JsonPrimitive(this)
    is Number -> JsonPrimitive(this)
    is String -> JsonPrimitive(this)
    is Map<*, *> -> @Suppress("UNCHECKED_CAST") (this as Map<String, Any?>).toJsonElement()
    is List<*> -> buildJsonArray { forEach { add(it.toJsonElement()) } }
    else -> JsonPrimitive(toString())
}

private fun JsonElement.toAnyMap(): Map<String, Any?> =
    jsonObject.mapValues { (_, v) -> v.toAny() }

private fun JsonElement.toAny(): Any? = when (this) {
    is JsonNull -> null
    is JsonPrimitive -> if (isString) content else booleanOrNull ?: longOrNull ?: doubleOrNull ?: content
    is JsonObject -> toAnyMap()
    is JsonArray -> map { it.toAny() }
}
''';

// ── InMemory cache store ──────────────────────────────────────────────────────

const kotlinInMemoryGraphLinkCacheStore = '''
import java.util.concurrent.ConcurrentHashMap

class InMemoryGraphLinkCacheStore : GraphLinkCacheStore {
    private val store = ConcurrentHashMap<String, String>()

    override fun set(key: String, value: String) { store[key] = value }
    override fun get(key: String): String? = store[key]
    override fun invalidate(key: String) { store.remove(key) }
    override fun invalidateAll() { store.clear() }
}
''';

// ── Default HTTP adapter (OkHttp) ─────────────────────────────────────────────

String kotlinDefaultGraphLinkClientAdapter(bool withOperationName) => '''
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

class DefaultGraphLinkClientAdapter(
    private val url: String,
    private val headersProvider: (() -> Map<String, String>)? = null,
    private val httpClient: OkHttpClient = OkHttpClient(),
) : GraphLinkClientAdapter {

    override suspend fun execute(payload: String${withOperationName ? ', operationName: String' : ''}): String =
        withContext(Dispatchers.IO) {
            val body = payload.toRequestBody("application/json".toMediaType())
            val builder = Request.Builder()
                .url(${withOperationName ? 'url + "?operationName=" + operationName' : 'url'})
                .post(body)
            headersProvider?.invoke()?.forEach { (k, v) -> builder.header(k, v) }
            httpClient.newCall(builder.build()).execute().use { it.body!!.string() }
        }
}
''';

String kotlinDefaultGraphLinkClientAdapterWithUpload(bool withOperationName) => '''
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okio.BufferedSink
import okio.buffer
import okio.source

class DefaultGraphLinkClientAdapter(
    private val url: String,
    private val headersProvider: (() -> Map<String, String>)? = null,
    private val httpClient: OkHttpClient = OkHttpClient(),
) : GraphLinkClientAdapter, GraphLinkMultipartAdapter {

    override suspend fun execute(payload: String${withOperationName ? ', operationName: String' : ''}): String =
        withContext(Dispatchers.IO) {
            val body = payload.toRequestBody("application/json".toMediaType())
            val builder = Request.Builder()
                .url(${withOperationName ? 'url + "?operationName=" + operationName' : 'url'})
                .post(body)
            headersProvider?.invoke()?.forEach { (k, v) -> builder.header(k, v) }
            httpClient.newCall(builder.build()).execute().use { it.body!!.string() }
        }

    override suspend fun executeMultipart(
        operations: String,
        mapJson: String,
        files: Map<String, GLUpload>,
        onProgress: UploadProgressCallback?,
    ): String = withContext(Dispatchers.IO) {
        val bodyBuilder = MultipartBody.Builder().setType(MultipartBody.FORM)
        bodyBuilder.addFormDataPart("operations", operations)
        bodyBuilder.addFormDataPart("map", mapJson)
        for ((key, upload) in files) {
            val fileBody: RequestBody = object : RequestBody() {
                override fun contentType() = upload.mimeType.toMediaType()
                override fun contentLength() = upload.length
                override fun writeTo(sink: BufferedSink) {
                    sink.writeAll(upload.stream.source())
                }
            }
            val uploadBody = if (onProgress != null) ProgressRequestBody(fileBody, onProgress) else fileBody
            bodyBuilder.addFormDataPart(key, upload.filename ?: key, uploadBody)
        }
        val reqBuilder = Request.Builder().url(url).post(bodyBuilder.build())
        headersProvider?.invoke()?.forEach { (k, v) -> reqBuilder.header(k, v) }
        httpClient.newCall(reqBuilder.build()).execute().use { it.body!!.string() }
    }

    private class ProgressRequestBody(
        private val delegate: RequestBody,
        private val callback: UploadProgressCallback,
    ) : RequestBody() {
        override fun contentType() = delegate.contentType()
        override fun contentLength() = delegate.contentLength()
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
''';

// ── Default WebSocket adapter (OkHttp) ────────────────────────────────────────

const kotlinDefaultGraphLinkWebSocketAdapter = '''
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.min

class DefaultGraphLinkWebSocketAdapter(
    private val url: String,
    private val headersProvider: (() -> Map<String, String>)? = null,
    private val httpClient: OkHttpClient = OkHttpClient(),
    private val maxReconnectAttempts: Int? = 10,
    private val maxReconnectDelayMs: Long = 30_000L,
    private val protocols: List<String> = listOf("graphql-transport-ws"),
) : GraphLinkWebSocketAdapter {

    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private val _reconnectAttempts = AtomicInteger(0)
    val reconnectAttempts: Int get() = _reconnectAttempts.get()

    @Volatile private var webSocket: WebSocket? = null
    @Volatile private var messageListener: ((String) -> Unit)? = null
    @Volatile private var reconnectListener: (() -> Unit)? = null
    @Volatile private var disposed = false

    override fun connect(onConnect: () -> Unit, onFailure: (Throwable) -> Unit) {
        disposed = false
        _reconnectAttempts.set(0)
        connectInternal(onConnect, onFailure)
    }

    private fun connectInternal(onConnect: () -> Unit, onFailure: (Throwable) -> Unit) {
        val builder = Request.Builder().url(url)
        if (protocols.isNotEmpty()) {
            builder.header("Sec-WebSocket-Protocol", protocols.joinToString(", "))
        }
        headersProvider?.invoke()?.forEach { (k, v) -> builder.header(k, v) }
        httpClient.newWebSocket(builder.build(), object : WebSocketListener() {
            override fun onOpen(ws: WebSocket, response: Response) {
                webSocket = ws
                onConnect()
            }
            override fun onMessage(ws: WebSocket, text: String) {
                messageListener?.invoke(text)
            }
            override fun onClosed(ws: WebSocket, code: Int, reason: String) {
                if (!disposed) scheduleReconnect(onFailure)
            }
            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                if (!disposed) scheduleReconnect(onFailure)
            }
        })
    }

    private fun scheduleReconnect(onFailure: (Throwable) -> Unit) {
        if (disposed) return
        val attempts = _reconnectAttempts.incrementAndGet()
        if (maxReconnectAttempts != null && attempts > maxReconnectAttempts) {
            onFailure(RuntimeException("Max reconnect attempts reached"))
            return
        }
        val baseDelay = min(1000L * (1L shl min(attempts - 1, 30)), maxReconnectDelayMs)
        val jitter = (Math.random() * 1000).toLong()
        scheduler.schedule({
            if (disposed) return@schedule
            connectInternal(
                onConnect = {
                    _reconnectAttempts.set(0)
                    reconnectListener?.invoke()
                },
                onFailure = onFailure,
            )
        }, baseDelay + jitter, TimeUnit.MILLISECONDS)
    }

    override fun sendMessage(message: String) { webSocket?.send(message) }
    override fun close() {
        disposed = true
        scheduler.shutdownNow()
        webSocket?.close(1000, null)
    }
    override fun setMessageListener(listener: (String) -> Unit) { messageListener = listener }
    override fun setReconnectListener(onReconnect: () -> Unit) { reconnectListener = onReconnect }
    override fun connectionInitPayload(): Map<String, Any?>? {
        val h = headersProvider?.invoke() ?: return null
        return if (h.isEmpty()) null else h.toMap()
    }
}
''';

// ── Subscription handler (Flow-based) ────────────────────────────────────────

const kotlinGraphLinkSubscriptionHandler = '''
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class GraphLinkSubscriptionHandler(
    private val adapter: GraphLinkWebSocketAdapter,
    private val decoder: GraphLinkJsonDecoder,
    private val encoder: GraphLinkJsonEncoder,
) {
    private val listeners = ConcurrentHashMap<String, (Map<String, Any?>) -> Unit>()
    private val payloadsToHandle = mutableMapOf<String, GraphLinkPayload>()
    private val activePayloads = mutableMapOf<String, GraphLinkPayload>()
    @Volatile private var ackStatus = GraphLinkAckStatus.NONE

    init {
        adapter.setMessageListener(::onMessage)
        adapter.setReconnectListener(::handleReconnect)
    }

    fun handle(payload: GraphLinkPayload): Flow<Map<String, Any?>> = callbackFlow {
        val uuid = UUID.randomUUID().toString()
        synchronized(this@GraphLinkSubscriptionHandler) {
            listeners[uuid] = { msg -> trySend(msg) }
            activePayloads[uuid] = payload
        }
        initConnection(uuid, payload)
        awaitClose {
            synchronized(this@GraphLinkSubscriptionHandler) {
                listeners.remove(uuid)
                activePayloads.remove(uuid)
            }
        }
    }

    private fun initConnection(id: String, payload: GraphLinkPayload) {
        var shouldConnect = false
        var shouldSend = false
        synchronized(this) {
            when (ackStatus) {
                GraphLinkAckStatus.NONE -> { payloadsToHandle[id] = payload; ackStatus = GraphLinkAckStatus.PROGRESS; shouldConnect = true }
                GraphLinkAckStatus.PROGRESS -> payloadsToHandle[id] = payload
                GraphLinkAckStatus.ACKNOWLEDGED -> shouldSend = true
            }
        }
        if (shouldConnect) {
            adapter.connect(
                onConnect = { adapter.sendMessage(getConnectionInit(id)) },
                onFailure = { notifyAllListenersOfError(it) },
            )
        } else if (shouldSend) {
            adapter.sendMessage(getSubscriptionMessage(id, payload))
        }
    }

    private fun getConnectionInit(id: String): String {
        val msg = mutableMapOf<String, Any?>("type" to GraphlinkWsMessageTypes.connectionInit, "id" to id)
        adapter.connectionInitPayload()?.let { msg["payload"] = it }
        return encoder.encode(msg)
    }

    private fun getSubscriptionMessage(id: String, payload: GraphLinkPayload): String =
        encoder.encode(mapOf(
            "type" to GraphlinkWsMessageTypes.subscribe,
            "id" to id,
            "payload" to mapOf(
                "query" to payload.query,
                "operationName" to payload.operationName,
                "variables" to payload.variables,
            ),
        ))

    private fun getPongMessage(id: String?): String =
        encoder.encode(mapOf("type" to GraphlinkWsMessageTypes.pong, "id" to id))

    private fun onMessage(message: String) {
        val map = decoder.decode(message)
        when (map["type"] as? String) {
            GraphlinkWsMessageTypes.connectionAck -> handleConnectionAck()
            GraphlinkWsMessageTypes.ping -> adapter.sendMessage(getPongMessage(map["id"] as? String))
            GraphlinkWsMessageTypes.next -> handleNextMessage(map)
            GraphlinkWsMessageTypes.error -> handleError(map)
            GraphlinkWsMessageTypes.complete -> handleComplete(map["id"] as? String)
        }
    }

    private fun handleConnectionAck() {
        val entries: List<Map.Entry<String, GraphLinkPayload>>
        synchronized(this) {
            ackStatus = GraphLinkAckStatus.ACKNOWLEDGED
            entries = payloadsToHandle.entries.toList()
            payloadsToHandle.clear()
        }
        for (e in entries) adapter.sendMessage(getSubscriptionMessage(e.key, e.value))
    }

    private fun handleNextMessage(map: Map<String, Any?>) {
        val id = map["id"] as? String ?: return
        @Suppress("UNCHECKED_CAST")
        val data = ((map["payload"] as? Map<*, *>) as? Map<String, Any?>)?.get("data")
                as? Map<String, Any?> ?: return
        listeners[id]?.invoke(data)
    }

    private fun handleError(map: Map<String, Any?>) {
        val id = map["id"] as? String ?: return
        listeners.remove(id)
        activePayloads.remove(id)
    }

    private fun handleComplete(id: String?) {
        if (id == null) return
        listeners.remove(id)
        activePayloads.remove(id)
    }

    private fun notifyAllListenersOfError(t: Throwable) {
        val snapshot: List<(Map<String, Any?>) -> Unit>
        synchronized(this) {
            snapshot = listeners.values.toList()
            listeners.clear()
            activePayloads.clear()
            payloadsToHandle.clear()
            ackStatus = GraphLinkAckStatus.NONE
        }
        snapshot.forEach { it(mapOf("__gl_error__" to t.message)) }
    }

    private fun handleReconnect() {
        val snapshot: Map<String, GraphLinkPayload>
        synchronized(this) {
            snapshot = HashMap(activePayloads)
            ackStatus = if (snapshot.isEmpty()) GraphLinkAckStatus.NONE else GraphLinkAckStatus.PROGRESS
            payloadsToHandle.putAll(snapshot)
        }
        if (snapshot.isNotEmpty()) {
            val firstId = snapshot.keys.first()
            adapter.sendMessage(getConnectionInit(firstId))
        }
    }
}
''';

// ── Upload ────────────────────────────────────────────────────────────────────

const kotlinGLUpload = '''
import java.io.InputStream

data class GLUpload(
    val stream: InputStream,
    val mimeType: String,
    val length: Long,
    val filename: String? = null,
)
''';

const kotlinUploadProgressCallback = '''
fun interface UploadProgressCallback {
    fun onProgress(sent: Long, total: Long)
}
''';

const kotlinSha256 = r'''
object GraphLinkSha256 {
    private val k = uintArrayOf(
        0x428a2f98u, 0x71374491u, 0xb5c0fbcfu, 0xe9b5dba5u, 0x3956c25bu, 0x59f111f1u, 0x923f82a4u, 0xab1c5ed5u,
        0xd807aa98u, 0x12835b01u, 0x243185beu, 0x550c7dc3u, 0x72be5d74u, 0x80deb1feu, 0x9bdc06a7u, 0xc19bf174u,
        0xe49b69c1u, 0xefbe4786u, 0x0fc19dc6u, 0x240ca1ccu, 0x2de92c6fu, 0x4a7484aau, 0x5cb0a9dcu, 0x76f988dau,
        0x983e5152u, 0xa831c66du, 0xb00327c8u, 0xbf597fc7u, 0xc6e00bf3u, 0xd5a79147u, 0x06ca6351u, 0x14292967u,
        0x27b70a85u, 0x2e1b2138u, 0x4d2c6dfcu, 0x53380d13u, 0x650a7354u, 0x766a0abbu, 0x81c2c92eu, 0x92722c85u,
        0xa2bfe8a1u, 0xa81a664bu, 0xc24b8b70u, 0xc76c51a3u, 0xd192e819u, 0xd6990624u, 0xf40e3585u, 0x106aa070u,
        0x19a4c116u, 0x1e376c08u, 0x2748774cu, 0x34b0bcb5u, 0x391c0cb3u, 0x4ed8aa4au, 0x5b9cca4fu, 0x682e6ff3u,
        0x748f82eeu, 0x78a5636fu, 0x84c87814u, 0x8cc70208u, 0x90befffau, 0xa4506cebu, 0xbef9a3f7u, 0xc67178f2u,
    )

    private fun rotr(x: UInt, n: Int): UInt = (x shr n) or (x shl (32 - n))

    private fun byteAt(bytes: ByteArray, index: Int): UInt = (bytes[index].toInt() and 0xFF).toUInt()

    fun hex(input: String): String {
        val data = input.encodeToByteArray()
        val bitLength = data.size.toLong() * 8
        val padded = ByteArray(((data.size + 9 + 63) / 64) * 64)
        data.copyInto(padded)
        padded[data.size] = 0x80.toByte()
        for (i in 0 until 8) {
            padded[padded.size - 1 - i] = (bitLength ushr (8 * i)).toByte()
        }

        val state = uintArrayOf(0x6a09e667u, 0xbb67ae85u, 0x3c6ef372u, 0xa54ff53au, 0x510e527fu, 0x9b05688cu, 0x1f83d9abu, 0x5be0cd19u)
        val w = UIntArray(64)
        for (offset in padded.indices step 64) {
            for (i in 0 until 16) {
                val j = offset + i * 4
                w[i] = (byteAt(padded, j) shl 24) or (byteAt(padded, j + 1) shl 16) or (byteAt(padded, j + 2) shl 8) or byteAt(padded, j + 3)
            }
            for (i in 16 until 64) {
                val s0 = rotr(w[i - 15], 7) xor rotr(w[i - 15], 18) xor (w[i - 15] shr 3)
                val s1 = rotr(w[i - 2], 17) xor rotr(w[i - 2], 19) xor (w[i - 2] shr 10)
                w[i] = w[i - 16] + s0 + w[i - 7] + s1
            }
            var a = state[0]
            var b = state[1]
            var c = state[2]
            var d = state[3]
            var e = state[4]
            var f = state[5]
            var g = state[6]
            var h = state[7]
            for (i in 0 until 64) {
                val s1 = rotr(e, 6) xor rotr(e, 11) xor rotr(e, 25)
                val ch = (e and f) xor (e.inv() and g)
                val t1 = h + s1 + ch + k[i] + w[i]
                val s0 = rotr(a, 2) xor rotr(a, 13) xor rotr(a, 22)
                val maj = (a and b) xor (a and c) xor (b and c)
                val t2 = s0 + maj
                h = g
                g = f
                f = e
                e = d + t1
                d = c
                c = b
                b = a
                a = t1 + t2
            }
            val working = uintArrayOf(a, b, c, d, e, f, g, h)
            for (i in 0 until 8) {
                state[i] = state[i] + working[i]
            }
        }
        return state.joinToString("") { it.toString(16).padStart(8, '0') }
    }
}
''';

const kotlinPersistedQueries = """
object GraphLinkPersistedQueries {
    const val MIN_QUERY_LENGTH = ${persistedQueryMinLength}
    const val NOT_FOUND = "PersistedQueryNotFound"
    const val NOT_SUPPORTED = "PersistedQueryNotSupported"

    fun extensions(hash: String): Map<String, Any?> =
        mapOf("persistedQuery" to mapOf("version" to 1, "sha256Hash" to hash))

    fun failure(response: String, decoder: GraphLinkJsonDecoder): String? {
        if (!response.contains("PersistedQuery") && !response.contains("PERSISTED_QUERY")) {
            return null
        }
        val errors = decoder.decode(response)["errors"] as? List<*> ?: return null
        for (error in errors) {
            val fields = error as? Map<*, *> ?: continue
            val code = (fields["extensions"] as? Map<*, *>)?.get("code")
            if (fields["message"] == NOT_FOUND || code == "PERSISTED_QUERY_NOT_FOUND") return NOT_FOUND
            if (fields["message"] == NOT_SUPPORTED || code == "PERSISTED_QUERY_NOT_SUPPORTED") return NOT_SUPPORTED
        }
        return null
    }
}
""";

const kotlinPersistedQueriesGet = '''
class GraphLinkGetNotSupported(message: String? = null) : Exception(message)

object GraphLinkGetRequest {
    fun queryParameters(
        payload: String,
        decoder: GraphLinkJsonDecoder,
        encoder: GraphLinkJsonEncoder,
    ): List<Pair<String, String>> {
        val body = decoder.decode(payload)
        val variables = body["variables"] as? Map<*, *>
        val parameters = mutableListOf<Pair<String, String>>()
        val operationName = body["operationName"]
        if (operationName != null) {
            parameters.add("operationName" to operationName.toString())
        }
        if (!variables.isNullOrEmpty()) {
            @Suppress("UNCHECKED_CAST")
            parameters.add("variables" to encoder.encode(variables as Map<String, Any?>))
        }
        @Suppress("UNCHECKED_CAST")
        parameters.add("extensions" to encoder.encode(body["extensions"] as Map<String, Any?>))
        return parameters
    }
}
''';

String kotlinDefaultGraphLinkGetAdapter(bool withOperationName) => '''
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request

class DefaultGraphLinkGetAdapter(
    private val url: String,
    private val headersProvider: (() -> Map<String, String>)? = null,
    private val httpClient: OkHttpClient = OkHttpClient(),
    private val codec: KotlinxSerializationGraphLinkJsonCodec = KotlinxSerializationGraphLinkJsonCodec(),
) : GraphLinkClientAdapter {

    override suspend fun execute(payload: String${withOperationName ? ', operationName: String' : ''}): String =
        withContext(Dispatchers.IO) {
            val target = url.toHttpUrl().newBuilder()
            for ((name, value) in GraphLinkGetRequest.queryParameters(payload, codec, codec)) {
                target.addQueryParameter(name, value)
            }
            val builder = Request.Builder().url(target.build()).get()
            headersProvider?.invoke()?.forEach { (k, v) -> builder.header(k, v) }
            httpClient.newCall(builder.build()).execute().use { response ->
                if (response.code == 405) {
                    throw GraphLinkGetNotSupported("GET is not allowed")
                }
                response.body!!.string()
            }
        }
}
''';
