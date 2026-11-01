class KotlinImports {
  // ── Standard library ────────────────────────────────────────────────────────
  static const objects = 'java.util.Objects';

  // ── Coroutines ───────────────────────────────────────────────────────────────
  static const flow = 'kotlinx.coroutines.flow.Flow';
  static const flowOf = 'kotlinx.coroutines.flow.flowOf';
  static const flowMap = 'kotlinx.coroutines.flow.map';
  static const flowBuilder = 'kotlinx.coroutines.flow.flow';
  static const flowEmitAll = 'kotlinx.coroutines.flow.emitAll';
  static const dispatchers = 'kotlinx.coroutines.Dispatchers';
  static const withContext = 'kotlinx.coroutines.withContext';

  // ── kotlinx.serialization ────────────────────────────────────────────────────
  static const json = 'kotlinx.serialization.json.Json';
  static const jsonElement = 'kotlinx.serialization.json.JsonElement';
  static const jsonObject = 'kotlinx.serialization.json.jsonObject';
  static const jsonArray = 'kotlinx.serialization.json.jsonArray';
  static const jsonPrimitive = 'kotlinx.serialization.json.JsonPrimitive';
  static const jsonNull = 'kotlinx.serialization.json.JsonNull';
  static const buildJsonObject = 'kotlinx.serialization.json.buildJsonObject';
  static const buildJsonArray = 'kotlinx.serialization.json.buildJsonArray';
  static const encodeToString = 'kotlinx.serialization.encodeToString';

  // ── OkHttp ───────────────────────────────────────────────────────────────────
  static const okHttpClient = 'okhttp3.OkHttpClient';
  static const okHttpRequest = 'okhttp3.Request';
  static const okHttpRequestBody = 'okhttp3.RequestBody';
  static const okHttpRequestBodyCompanion = 'okhttp3.RequestBody.Companion.toRequestBody';
  static const okHttpMediaType = 'okhttp3.MediaType.Companion.toMediaType';
  static const okHttpResponse = 'okhttp3.Response';
  static const okHttpWebSocket = 'okhttp3.WebSocket';
  static const okHttpWebSocketListener = 'okhttp3.WebSocketListener';
  static const okHttpMultipartBody = 'okhttp3.MultipartBody';

  // ── OkHttp Coroutine extensions (okhttp-coroutines or manual) ────────────────
  static const okHttpExecute = 'okhttp3.execute';

  // ── File upload ──────────────────────────────────────────────────────────────
  static const inputStream = 'java.io.InputStream';
  static const file = 'java.io.File';
}
