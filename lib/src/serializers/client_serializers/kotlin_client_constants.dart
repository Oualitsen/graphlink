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

const kotlinGraphLinkPayload = '''
data class GraphLinkPayload(
    val query: String,
    val operationName: String,
    val variables: Map<String, Any?>,
)
''';

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
import okio.Okio

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
                    sink.writeAll(Okio.source(upload.stream))
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
            val buffered = Okio.buffer(counting)
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

class DefaultGraphLinkWebSocketAdapter(
    private val url: String,
    private val headersProvider: (() -> Map<String, String>)? = null,
    private val httpClient: OkHttpClient = OkHttpClient(),
) : GraphLinkWebSocketAdapter {

    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private val reconnectAttempts = AtomicInteger(0)

    @Volatile private var webSocket: WebSocket? = null
    @Volatile private var messageListener: ((String) -> Unit)? = null
    @Volatile private var reconnectListener: (() -> Unit)? = null

    override fun connect(onConnect: () -> Unit, onFailure: (Throwable) -> Unit) {
        reconnectAttempts.set(0)
        connectInternal(onConnect, onFailure)
    }

    private fun connectInternal(onConnect: () -> Unit, onFailure: (Throwable) -> Unit) {
        val builder = Request.Builder().url(url)
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
                scheduleReconnect(onFailure)
            }
            override fun onFailure(ws: WebSocket, t: Throwable, response: Response?) {
                scheduleReconnect(onFailure)
            }
        })
    }

    private fun scheduleReconnect(onFailure: (Throwable) -> Unit) {
        val attempts = reconnectAttempts.incrementAndGet()
        val delay = Math.pow(2.0, minOf(attempts, 5).toDouble()).toLong()
        scheduler.schedule({
            connectInternal({ reconnectListener?.invoke() }, onFailure)
        }, delay, TimeUnit.SECONDS)
    }

    override fun sendMessage(message: String) { webSocket?.send(message) }
    override fun close() {
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
