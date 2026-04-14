const subscriptionListenerName = 'GraphLinkSubscriptionListener';
const subscriptionListenerRef = subscriptionListenerName;
const clientName = 'GraphLinkClient';
const clientExceptionName = 'GraphLinkException';
const clientExceptionNameRef = clientExceptionName;

const gqSubscriptionListener = '''
public interface ${subscriptionListenerName}<T> {
  void onMessage(T response) ;
  default void  onComplete(){}
  default void  onError(${clientExceptionNameRef} error) {}
}
''';

const graphqlWsMessageTypesClass = '''
public class GraphqlWsMessageTypes {
  /// Client initializes connection.
  /// Example: { "type": "connection_init", "payload": { "authToken": "abc123" } }
  public static final String connectionInit = "connection_init";

  /// Server acknowledges connection.
  /// Example: { "type": "connection_ack" }
  public static final String connectionAck = "connection_ack";

  /// Client subscribes to an operation.
  /// Example:
  /// {
  ///   "id": "1",
  ///   "type": "subscribe",
  ///   "payload": { "query": "...", "variables": {} }
  /// }
  public static final String subscribe = "subscribe";

  /// Client or server pings for keep-alive.
  /// Example: { "type": "ping", "payload": {} }
  public static final String ping = "ping";

  /// Response to ping.
  /// Example: { "type": "pong" }
  public static final String pong = "pong";

  /// Server sends subscription data.
  /// Example:
  /// {
  ///   "id": "1",
  ///   "type": "next",
  ///   "payload": { "data": { "newMessage": { "id": "42", "content": "Hi" } } }
  /// }
  public static final String next = "next";

  /// Server sends a fatal error for a subscription.
  /// Example: { "id": "1", "type": "error", "payload": { "message": "Validation failed" } }
  public static final String error = "error";

  /// Client or server completes subscription.
  /// Example: { "id": "1", "type": "complete" }
  public static final String complete = "complete";
}
''';

const subscriptionHandlerClass = '''
public class GraphLinkSubscriptionHandler {

  private final Map<String, ${subscriptionListenerRef}<Map<String, Object>>> listeners = new HashMap<>();
  private final Map<String, GraphLinkPayload> payloadsToHandle = new HashMap<>();
  private final Map<String, GraphLinkPayload> activePayloads = new HashMap<>();

  private final GraphLinkWebSocketAdapter adapter;
  private final GraphLinkJsonDecoder decoder;
  private final GraphLinkJsonEncoder encoder;
  private GraphLinkAckStatus ackStatus = GraphLinkAckStatus.none;

  GraphLinkSubscriptionHandler(GraphLinkWebSocketAdapter adapter, GraphLinkJsonDecoder decoder, GraphLinkJsonEncoder encoder) {
    this.adapter = adapter;
    this.decoder = decoder;
    this.encoder = encoder;
    adapter.setMessageListener(this::onMessage);
    adapter.setReconnectListener(this::handleReconnect);
  }

  String getConnectionInit(String id) {
    Map<String, Object> initPayload = adapter.connectionInitPayload();
    Map<String, Object> message = new HashMap<>();
    message.put("type", GraphqlWsMessageTypes.connectionInit);
    if (id != null) message.put("id", id);
    if (initPayload != null) message.put("payload", initPayload);
    return encoder.encode(message);
  }

  String getPongMessage(String id) {
    return encoder.encode(GraphLinkSubscriptionMessage.builder()
        .type(GraphqlWsMessageTypes.pong)
        .id(id)
        .build());
  }

  String getSubscriptionMessage(String id, GraphLinkPayload payload) {
    GraphLinkSubscriptionPayload subscriptionPayload = GraphLinkSubscriptionPayload.builder()
        .query(payload.getQuery())
        .operationName(payload.getOperationName())
        .variables(payload.getVariables())
        .build();
    return encoder.encode(GraphLinkSubscriptionMessage.builder()
        .type(GraphqlWsMessageTypes.subscribe)
        .payload(subscriptionPayload)
        .id(id)
        .build());
  }

  public void initConnection(String id, GraphLinkPayload payload) {
    boolean shouldConnect = false;
    boolean shouldSend = false;
    synchronized (this) {
      switch (ackStatus) {
        case none:
          payloadsToHandle.put(id, payload);
          ackStatus = GraphLinkAckStatus.progress;
          shouldConnect = true;
          break;
        case progress:
          payloadsToHandle.put(id, payload);
          break;
        case acknoledged:
          shouldSend = true;
          break;
      }
    }
    if (shouldConnect) {
      adapter.connect(() -> {
        adapter.sendMessage(getConnectionInit(id));
      }, (t) -> {
        notifyAllListenersOfError(t);
      });
    } else if (shouldSend) {
      adapter.sendMessage(getSubscriptionMessage(id, payload));
    }
  }

  private GraphLinkSubscriptionErrorMessageBase parseEvent(String event) {
    Map<String, Object> map = decoder.decode(event);
    Object payload = map.get("payload");
    if (payload instanceof Map) {
      return GraphLinkSubscriptionMessage.fromJson(map);
    } else {
      return GraphLinkSubscriptionErrorMessage.fromJson(map);
    }
  }

  public void handlePayload(GraphLinkPayload payload, ${subscriptionListenerRef}<Map<String, Object>> listener) {
    String uuid = UUID.randomUUID().toString();
    synchronized (this) {
      listeners.put(uuid, listener);
      activePayloads.put(uuid, payload);
    }
    initConnection(uuid, payload);
  }

  public void onMessage(String message) {
    GraphLinkSubscriptionErrorMessageBase event = parseEvent(message);
    String type = event.getType();
    switch (type) {
      case GraphqlWsMessageTypes.connectionAck:
        handleConnectionAck();
        break;
      case GraphqlWsMessageTypes.subscribe:
        break;
      case GraphqlWsMessageTypes.ping:
        adapter.sendMessage(getPongMessage(event.getId()));
        break;
      case GraphqlWsMessageTypes.next:
        handleNextMessage((GraphLinkSubscriptionMessage) event);
        break;
      case GraphqlWsMessageTypes.error:
        handleError((GraphLinkSubscriptionErrorMessage) event);
        break;
      case GraphqlWsMessageTypes.complete:
        handleComplete(event.getId());
        break;
    }
  }

  void handleError(GraphLinkSubscriptionErrorMessage error) {
    ${subscriptionListenerRef}<Map<String, Object>> listener;
    synchronized (this) {
      listener = listeners.remove(error.getId());
      activePayloads.remove(error.getId());
    }
    if (listener != null) {
      listener.onError(new ${clientExceptionNameRef}(error.getPayload()));
    }
  }

  void handleComplete(String id) {
    ${subscriptionListenerRef}<Map<String, Object>> removedListener;
    synchronized (this) {
      removedListener = listeners.remove(id);
      activePayloads.remove(id);
    }
    if (removedListener != null) {
      removedListener.onComplete();
    }
  }

  private void notifyAllListenersOfError(Throwable t) {
    List<${subscriptionListenerRef}<Map<String, Object>>> snapshot;
    synchronized (this) {
      snapshot = new ArrayList<>(listeners.values());
      listeners.clear();
      activePayloads.clear();
      payloadsToHandle.clear();
      ackStatus = GraphLinkAckStatus.none;
    }
    ${clientExceptionNameRef} error = ${clientExceptionNameRef}.of(Collections.singletonList(Collections.singletonMap("message", t.getMessage())));
    for (${subscriptionListenerRef}<Map<String, Object>> listener : snapshot) {
      listener.onError(error);
    }
  }

  private void handleReconnect() {
    Map<String, GraphLinkPayload> snapshot;
    synchronized (this) {
      snapshot = new HashMap<>(activePayloads);
      ackStatus = snapshot.isEmpty() ? GraphLinkAckStatus.none : GraphLinkAckStatus.progress;
      payloadsToHandle.putAll(snapshot);
    }
    if (!snapshot.isEmpty()) {
      String firstId = snapshot.keySet().iterator().next();
      adapter.sendMessage(getConnectionInit(firstId));
    }
  }

  void handleConnectionAck() {
    List<Map.Entry<String, GraphLinkPayload>> entries;
    synchronized (this) {
      this.ackStatus = GraphLinkAckStatus.acknoledged;
      entries = new ArrayList<>(payloadsToHandle.entrySet());
      payloadsToHandle.clear();
    }
    for (Map.Entry<String, GraphLinkPayload> entry : entries) {
      adapter.sendMessage(getSubscriptionMessage(entry.getKey(), entry.getValue()));
    }
  }

  private void handleNextMessage(GraphLinkSubscriptionMessage message) {
    String id = message.getId();
    ${subscriptionListenerRef}<Map<String, Object>> listener;
    synchronized (this) {
      listener = listeners.get(id);
    }
    if (listener != null) {
      listener.onMessage(message.getPayload().getData());
    }
  }

}
''';

const defaultWsAdapterJava11 = '''
public class DefaultGraphLinkWebSocketAdapter implements GraphLinkWebSocketAdapter {

  private static final int MAX_BACKOFF_EXPONENT = 5;

  private final String url;
  private final Supplier<Map<String, String>> headersProvider;
  private final HttpClient httpClient;
  private final ScheduledExecutorService scheduler = Executors.newSingleThreadScheduledExecutor();

  private volatile WebSocket webSocket;
  private volatile Consumer<String> messageListener;
  private volatile Runnable reconnectListener;
  private final AtomicInteger reconnectAttempts = new AtomicInteger(0);

  public DefaultGraphLinkWebSocketAdapter(String url) {
    this(url, null, HttpClient.newHttpClient());
  }

  public DefaultGraphLinkWebSocketAdapter(String url, Supplier<Map<String, String>> headersProvider) {
    this(url, headersProvider, HttpClient.newHttpClient());
  }

  public DefaultGraphLinkWebSocketAdapter(String url, Supplier<Map<String, String>> headersProvider, HttpClient httpClient) {
    this.url = url;
    this.headersProvider = headersProvider;
    this.httpClient = httpClient;
  }

  @Override
  public void connect(Runnable onConnect, Consumer<Throwable> onFailure) {
    reconnectAttempts.set(0);
    connectInternal(onConnect, onFailure);
  }

  private void connectInternal(Runnable onConnect, Consumer<Throwable> onFailure) {
    java.net.http.WebSocket.Builder wsBuilder = httpClient.newWebSocketBuilder();
        
    if (headersProvider != null) {
      Map<String, String> h = headersProvider.get();
      if (h != null) h.forEach(wsBuilder::header);
    }
    wsBuilder.buildAsync(URI.create(url), new WebSocket.Listener() {
          private final StringBuilder buffer = new StringBuilder();

          @Override
          public void onOpen(WebSocket ws) {
            webSocket = ws;
            ws.request(1);
            onConnect.run();
          }

          @Override
          public CompletionStage<?> onText(WebSocket ws, CharSequence data, boolean last) {
            buffer.append(data);
            ws.request(1);
            if (last) {
              String message = buffer.toString();
              buffer.setLength(0);
              Consumer<String> listener = messageListener;
              if (listener != null) listener.accept(message);
            }
            return CompletableFuture.completedFuture(null);
          }

          @Override
          public CompletionStage<?> onClose(WebSocket ws, int statusCode, String reason) {
            scheduleReconnect(onFailure);
            return CompletableFuture.completedFuture(null);
          }

          @Override
          public void onError(WebSocket ws, Throwable error) {
            scheduleReconnect(onFailure);
          }
        });
  }

  private void scheduleReconnect(Consumer<Throwable> onFailure) {
    int attempts = reconnectAttempts.incrementAndGet();
    long delaySeconds = (long) Math.pow(2, Math.min(attempts, MAX_BACKOFF_EXPONENT));
    scheduler.schedule(() -> connectInternal(() -> {
      Runnable listener = reconnectListener;
      if (listener != null) listener.run();
    }, onFailure), delaySeconds, TimeUnit.SECONDS);
  }

  @Override
  public void setMessageListener(Consumer<String> listener) {
    this.messageListener = listener;
  }

  @Override
  public void sendMessage(String message) {
    WebSocket ws = webSocket;
    if (ws != null) ws.sendText(message, true);
  }

  @Override
  public void close() {
    scheduler.shutdownNow();
    WebSocket ws = webSocket;
    if (ws != null) ws.sendClose(WebSocket.NORMAL_CLOSURE, "");
  }

  @Override
  public Map<String, Object> connectionInitPayload() {
    if (headersProvider == null) return null;
    Map<String, String> headers = headersProvider.get();
    if (headers == null || headers.isEmpty()) return null;
    return new HashMap<>(headers);
  }

  @Override
  public void setReconnectListener(Runnable onReconnect) {
    this.reconnectListener = onReconnect;
  }
}
''';

const defaultWsAdapterOkHttp = '''
public class DefaultGraphLinkWebSocketAdapter implements GraphLinkWebSocketAdapter {

  private static final int MAX_BACKOFF_EXPONENT = 5;

  private final String url;
  private final Supplier<Map<String, String>> headersProvider;
  private final OkHttpClient httpClient;
  private final ScheduledExecutorService scheduler = Executors.newSingleThreadScheduledExecutor();

  private volatile WebSocket webSocket;
  private volatile Consumer<String> messageListener;
  private volatile Runnable reconnectListener;
  private final AtomicInteger reconnectAttempts = new AtomicInteger(0);

  public DefaultGraphLinkWebSocketAdapter(String url) {
    this(url, null, new OkHttpClient());
  }

  public DefaultGraphLinkWebSocketAdapter(String url, Supplier<Map<String, String>> headersProvider) {
    this(url, headersProvider, new OkHttpClient());
  }

  public DefaultGraphLinkWebSocketAdapter(String url, Supplier<Map<String, String>> headersProvider, OkHttpClient httpClient) {
    this.url = url;
    this.headersProvider = headersProvider;
    this.httpClient = httpClient;
  }

  protected Request buildRequest() {
    Request.Builder builder = new Request.Builder()
        .url(url);
    if (headersProvider != null) {
      Map<String, String> headers = headersProvider.get();
      if (headers != null) headers.forEach(builder::header);
    }
    return builder.build();
  }

  @Override
  public void connect(Runnable onConnect, Consumer<Throwable> onFailure) {
    reconnectAttempts.set(0);
    connectInternal(onConnect, onFailure);
  }

  private void connectInternal(Runnable onConnect, Consumer<Throwable> onFailure) {
    httpClient.newWebSocket(buildRequest(), new WebSocketListener() {
      @Override
      public void onOpen(WebSocket ws, Response response) {
        webSocket = ws;
        onConnect.run();
      }

      @Override
      public void onMessage(WebSocket ws, String text) {
        Consumer<String> listener = messageListener;
        if (listener != null) listener.accept(text);
      }

      @Override
      public void onClosed(WebSocket ws, int code, String reason) {
        scheduleReconnect(onFailure);
      }

      @Override
      public void onFailure(WebSocket ws, Throwable t, Response response) {
        scheduleReconnect(onFailure);
      }
    });
  }

  private void scheduleReconnect(Consumer<Throwable> onFailure) {
    int attempts = reconnectAttempts.incrementAndGet();
    long delaySeconds = (long) Math.pow(2, Math.min(attempts, MAX_BACKOFF_EXPONENT));
    scheduler.schedule(() -> connectInternal(() -> {
      Runnable listener = reconnectListener;
      if (listener != null) listener.run();
    }, onFailure), delaySeconds, TimeUnit.SECONDS);
  }

  @Override
  public void setMessageListener(Consumer<String> listener) {
    this.messageListener = listener;
  }

  @Override
  public void sendMessage(String message) {
    WebSocket ws = webSocket;
    if (ws != null) ws.send(message);
  }

  @Override
  public void close() {
    scheduler.shutdownNow();
    WebSocket ws = webSocket;
    if (ws != null) ws.close(1000, null);
  }

  @Override
  public Map<String, Object> connectionInitPayload() {
    if (headersProvider == null) return null;
    Map<String, String> headers = headersProvider.get();
    if (headers == null || headers.isEmpty()) return null;
    return new HashMap<>(headers);
  }

  @Override
  public void setReconnectListener(Runnable onReconnect) {
    this.reconnectListener = onReconnect;
  }
}
''';

const defaultClientAdapterJava11 = '''
public class DefaultGraphLinkClientAdapter implements GraphLinkClientAdapter {

  private final String url;
  private final Supplier<Map<String, String>> headersProvider;
  private final HttpClient httpClient;

  public DefaultGraphLinkClientAdapter(String url, Supplier<Map<String, String>> headersProvider) {
    this(url, headersProvider, HttpClient.newHttpClient());
  }

  public DefaultGraphLinkClientAdapter(String url) {
    this(url, null, HttpClient.newHttpClient());
  }

  public DefaultGraphLinkClientAdapter(String url, Supplier<Map<String, String>> headersProvider, HttpClient httpClient) {
    this.url = url;
    this.headersProvider = headersProvider;
    this.httpClient = httpClient;
  }

  @Override
  public String execute(String payload) {
    try {
      HttpRequest.Builder builder = HttpRequest.newBuilder()
          .uri(URI.create(url))
          .header("Content-Type", "application/json")
          .POST(HttpRequest.BodyPublishers.ofString(payload));
      if (headersProvider != null) {
        Map<String, String> headers = headersProvider.get();
        if (headers != null) headers.forEach(builder::header);
      }
      HttpResponse<String> response = httpClient.send(builder.build(), HttpResponse.BodyHandlers.ofString());
      return response.body();
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }
}
''';

const defaultClientAdapterOkHttp = '''
public class DefaultGraphLinkClientAdapter implements GraphLinkClientAdapter {

  private static final MediaType JSON = MediaType.get("application/json");

  private final String url;
  private final Supplier<Map<String, String>> headersProvider;
  private final OkHttpClient httpClient;

  public DefaultGraphLinkClientAdapter(String url, Supplier<Map<String, String>> headersProvider) {
    this(url, headersProvider, new OkHttpClient());
  }

  public DefaultGraphLinkClientAdapter(String url) {
    this(url, null, new OkHttpClient());
  }

  public DefaultGraphLinkClientAdapter(String url, Supplier<Map<String, String>> headersProvider, OkHttpClient httpClient) {
    this.url = url;
    this.headersProvider = headersProvider;
    this.httpClient = httpClient;
  }

  @Override
  public String execute(String payload) {
    try {
      Request.Builder builder = new Request.Builder()
          .url(url)
          .post(RequestBody.create(payload, JSON));
      if (headersProvider != null) {
        Map<String, String> headers = headersProvider.get();
        if (headers != null) headers.forEach(builder::header);
      }
      try (Response response = httpClient.newCall(builder.build()).execute()) {
        return response.body().string();
      }
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }
}
''';

const defaultClientAdapterOkHttpWithUpload = '''
public class DefaultGraphLinkClientAdapter implements GraphLinkClientAdapter, GraphLinkMultipartAdapter {

  private static final MediaType JSON = MediaType.get("application/json");

  private final String url;
  private final Supplier<Map<String, String>> headersProvider;
  private final OkHttpClient httpClient;

  public DefaultGraphLinkClientAdapter(String url, Supplier<Map<String, String>> headersProvider) {
    this(url, headersProvider, new OkHttpClient());
  }

  public DefaultGraphLinkClientAdapter(String url) {
    this(url, null, new OkHttpClient());
  }

  public DefaultGraphLinkClientAdapter(String url, Supplier<Map<String, String>> headersProvider, OkHttpClient httpClient) {
    this.url = url;
    this.headersProvider = headersProvider;
    this.httpClient = httpClient;
  }

  @Override
  public String execute(String payload) {
    try {
      Request.Builder builder = new Request.Builder()
          .url(url)
          .post(RequestBody.create(payload, JSON));
      if (headersProvider != null) {
        Map<String, String> headers = headersProvider.get();
        if (headers != null) headers.forEach(builder::header);
      }
      try (Response response = httpClient.newCall(builder.build()).execute()) {
        return response.body().string();
      }
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }

  @Override
  public String executeMultipart(String operations, String mapJson, Map<String, GLUpload> files, UploadProgressCallback onProgress) throws IOException {
    MultipartBody.Builder bodyBuilder = new MultipartBody.Builder().setType(MultipartBody.FORM);
    bodyBuilder.addFormDataPart("operations", operations);
    bodyBuilder.addFormDataPart("map", mapJson);
    for (Map.Entry<String, GLUpload> entry : files.entrySet()) {
      GLUpload upload = entry.getValue();
      RequestBody fileBody = new RequestBody() {
        @Override public MediaType contentType() { return MediaType.parse(upload.getMimeType()); }
        @Override public long contentLength() { return upload.getLength(); }
        @Override public void writeTo(okio.BufferedSink sink) throws IOException {
          sink.writeAll(okio.Okio.source(upload.getStream()));
        }
      };
      RequestBody uploadBody = onProgress != null ? new ProgressRequestBody(fileBody, onProgress) : fileBody;
      String filename = upload.getFilename() != null ? upload.getFilename() : entry.getKey();
      bodyBuilder.addFormDataPart(entry.getKey(), filename, uploadBody);
    }
    Request.Builder reqBuilder = new Request.Builder().url(url).post(bodyBuilder.build());
    if (headersProvider != null) {
      Map<String, String> headers = headersProvider.get();
      if (headers != null) headers.forEach(reqBuilder::header);
    }
    try (Response response = httpClient.newCall(reqBuilder.build()).execute()) {
      return response.body().string();
    }
  }

  private static final class ProgressRequestBody extends RequestBody {
    private final RequestBody delegate;
    private final UploadProgressCallback callback;

    ProgressRequestBody(RequestBody delegate, UploadProgressCallback callback) {
      this.delegate = delegate;
      this.callback = callback;
    }

    @Override public MediaType contentType() { return delegate.contentType(); }
    @Override public long contentLength() throws IOException { return delegate.contentLength(); }

    @Override
    public void writeTo(okio.BufferedSink sink) throws IOException {
      final long total = contentLength();
      final long[] sent = {0};
      okio.BufferedSink countingSink = okio.Okio.buffer(new okio.ForwardingSink(sink) {
        @Override public void write(okio.Buffer source, long byteCount) throws IOException {
          super.write(source, byteCount);
          sent[0] += byteCount;
          callback.onProgress(sent[0], total);
        }
      });
      delegate.writeTo(countingSink);
      countingSink.flush();
    }
  }
}
''';

const defaultClientAdapterJava11WithUpload = '''
public class DefaultGraphLinkClientAdapter implements GraphLinkClientAdapter, GraphLinkMultipartAdapter {

  private final String url;
  private final Supplier<Map<String, String>> headersProvider;
  private final HttpClient httpClient;

  public DefaultGraphLinkClientAdapter(String url, Supplier<Map<String, String>> headersProvider) {
    this(url, headersProvider, HttpClient.newHttpClient());
  }

  public DefaultGraphLinkClientAdapter(String url) {
    this(url, null, HttpClient.newHttpClient());
  }

  public DefaultGraphLinkClientAdapter(String url, Supplier<Map<String, String>> headersProvider, HttpClient httpClient) {
    this.url = url;
    this.headersProvider = headersProvider;
    this.httpClient = httpClient;
  }

  @Override
  public String execute(String payload) {
    try {
      HttpRequest.Builder builder = HttpRequest.newBuilder()
          .uri(URI.create(url))
          .header("Content-Type", "application/json")
          .POST(HttpRequest.BodyPublishers.ofString(payload));
      if (headersProvider != null) {
        Map<String, String> headers = headersProvider.get();
        if (headers != null) headers.forEach(builder::header);
      }
      HttpResponse<String> response = httpClient.send(builder.build(), HttpResponse.BodyHandlers.ofString());
      return response.body();
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }

  @Override
  public String executeMultipart(String operations, String mapJson, Map<String, GLUpload> files, UploadProgressCallback onProgress) throws IOException {
    String boundary = "----GraphLinkBoundary" + java.util.UUID.randomUUID().toString().replace("-", "");
    byte[] body = buildMultipartBody(boundary, operations, mapJson, files);
    HttpRequest.BodyPublisher basePublisher = HttpRequest.BodyPublishers.ofByteArray(body);
    HttpRequest.BodyPublisher publisher = onProgress != null
        ? new CountingBodyPublisher(basePublisher, body.length, onProgress)
        : basePublisher;
    HttpRequest.Builder reqBuilder = HttpRequest.newBuilder()
        .uri(URI.create(url))
        .header("Content-Type", "multipart/form-data; boundary=" + boundary)
        .POST(publisher);
    if (headersProvider != null) {
      Map<String, String> headers = headersProvider.get();
      if (headers != null) headers.forEach(reqBuilder::header);
    }
    try {
      HttpResponse<String> response = httpClient.send(reqBuilder.build(), HttpResponse.BodyHandlers.ofString());
      return response.body();
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw new java.io.IOException(e);
    }
  }

  private byte[] buildMultipartBody(String boundary, String operations, String mapJson, Map<String, GLUpload> files) throws IOException {
    java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
    writePart(out, boundary, "operations", "application/json", operations.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    writePart(out, boundary, "map", "application/json", mapJson.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    for (Map.Entry<String, GLUpload> entry : files.entrySet()) {
      GLUpload upload = entry.getValue();
      String filename = upload.getFilename() != null ? upload.getFilename() : entry.getKey();
      out.write(("--" + boundary + "\\r\\n").getBytes(java.nio.charset.StandardCharsets.UTF_8));
      out.write(("Content-Disposition: form-data; name=\\"" + entry.getKey() + "\\"; filename=\\"" + filename + "\\"\\r\\n").getBytes(java.nio.charset.StandardCharsets.UTF_8));
      out.write(("Content-Type: " + upload.getMimeType() + "\\r\\n\\r\\n").getBytes(java.nio.charset.StandardCharsets.UTF_8));
      upload.getStream().transferTo(out);
      out.write("\\r\\n".getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }
    out.write(("--" + boundary + "--\\r\\n").getBytes(java.nio.charset.StandardCharsets.UTF_8));
    return out.toByteArray();
  }

  private void writePart(java.io.ByteArrayOutputStream out, String boundary, String name, String contentType, byte[] data) throws IOException {
    out.write(("--" + boundary + "\\r\\n").getBytes(java.nio.charset.StandardCharsets.UTF_8));
    out.write(("Content-Disposition: form-data; name=\\"" + name + "\\"\\r\\n").getBytes(java.nio.charset.StandardCharsets.UTF_8));
    out.write(("Content-Type: " + contentType + "\\r\\n\\r\\n").getBytes(java.nio.charset.StandardCharsets.UTF_8));
    out.write(data);
    out.write("\\r\\n".getBytes(java.nio.charset.StandardCharsets.UTF_8));
  }

  private static final class CountingBodyPublisher implements HttpRequest.BodyPublisher {
    private final HttpRequest.BodyPublisher delegate;
    private final long total;
    private final UploadProgressCallback callback;

    CountingBodyPublisher(HttpRequest.BodyPublisher delegate, long total, UploadProgressCallback callback) {
      this.delegate = delegate;
      this.total = total;
      this.callback = callback;
    }

    @Override public long contentLength() { return delegate.contentLength(); }

    @Override
    public void subscribe(java.util.concurrent.Flow.Subscriber<? super java.nio.ByteBuffer> subscriber) {
      delegate.subscribe(new java.util.concurrent.Flow.Subscriber<>() {
        long sent = 0;
        @Override public void onSubscribe(java.util.concurrent.Flow.Subscription sub) { subscriber.onSubscribe(sub); }
        @Override public void onNext(java.nio.ByteBuffer item) {
          sent += item.remaining();
          callback.onProgress(sent, total);
          subscriber.onNext(item);
        }
        @Override public void onError(Throwable t) { subscriber.onError(t); }
        @Override public void onComplete() { subscriber.onComplete(); }
      });
    }
  }
}
''';

const jacksonCodecClass = '''
public class JacksonGraphLinkJsonCodec implements GraphLinkJsonEncoder, GraphLinkJsonDecoder {

  private final ObjectMapper mapper;

  public JacksonGraphLinkJsonCodec() {
    this(new ObjectMapper());
  }

  public JacksonGraphLinkJsonCodec(ObjectMapper mapper) {
    this.mapper = mapper;
  }

  @Override
  public String encode(Object obj) {
    try {
      return mapper.writeValueAsString(obj);
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }

  @Override
  @SuppressWarnings("unchecked")
  public Map<String, Object> decode(String json) {
    try {
      return mapper.readValue(json, Map.class);
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }
}
''';

const gsonCodecClass = '''
public class GsonGraphLinkJsonCodec implements GraphLinkJsonEncoder, GraphLinkJsonDecoder {

  private final Gson gson;

  public GsonGraphLinkJsonCodec() {
    this(new Gson());
  }

  public GsonGraphLinkJsonCodec(Gson gson) {
    this.gson = gson;
  }

  @Override
  public String encode(Object obj) {
    return gson.toJson(obj);
  }

  @Override
  @SuppressWarnings("unchecked")
  public Map<String, Object> decode(String json) {
    return gson.fromJson(json, Map.class);
  }
}
''';
