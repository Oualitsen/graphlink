const dartSubscriptionHandler = """

enum _HandshakeStatus { none, progress, acknowledged }

class _SubscriptionHandler {
  static const hexDigits = '0123456789abcdef';
  final _random = Random();
  final Map<String, StreamController<Map<String, dynamic>>> _map = {};
  final Map<String, StreamSubscription> _subs = {};
  final Map<String, GraphLinkPayload> _payloads = {};
  final GraphLinkWebSocketAdapter adapter;

  final pongMessage = jsonEncode(GraphLinkSubscriptionErrorMessage(type: GraphqlWsMessageTypes.pong).toJson());

  _SubscriptionHandler(this.adapter) {
    adapter.onReconnect.listen((_) => _onReconnect());
  }

  Completer<_StreamSink>? _sinkCompleter;
  _HandshakeStatus _handshakeStatus = _HandshakeStatus.none;
  Completer<_StreamSink>? _handshakeCompleter;

  late final _onMessageStream = adapter.onMessageStream;

  Future<_StreamSink> _initWs() {
    if (_sinkCompleter != null) return _sinkCompleter!.future;
    _sinkCompleter = Completer();
    _connect();
    return _sinkCompleter!.future;
  }

  Future<void> _connect() async {
    final completer = _sinkCompleter;
    try {
      await adapter.connect();
      if (_handshakeStatus == _HandshakeStatus.acknowledged) {
        completer?.complete(_StreamSink(sendMessage: adapter.sendMessage, stream: _onMessageStream));
      } else {
        completer?.complete(await _doHandshake());
      }
    } catch (e) {
      completer?.completeError(e);
      _sinkCompleter = null;
    }
  }

  Future<_StreamSink> _doHandshake() {
    if (_handshakeCompleter != null) return _handshakeCompleter!.future;
    _handshakeCompleter = Completer();
    _handshakeStatus = _HandshakeStatus.progress;
    _performHandshake().then((sink) {
      _handshakeCompleter?.complete(sink);
      _handshakeCompleter = null;
    }).catchError((e) {
      _handshakeCompleter?.completeError(e);
      _handshakeCompleter = null;
    });
    return _handshakeCompleter!.future;
  }

  Future<_StreamSink> _performHandshake() async {
    try {
      final payload = await adapter.connectionInitPayload();
      final initMsg = jsonEncode({
        'type': GraphqlWsMessageTypes.connectionInit,
        if (payload != null) 'payload': payload,
      });
      await adapter.sendMessage(initMsg);
      await _onMessageStream
          .map(_parseEvent)
          .firstWhere(
            (msg) => msg.type == GraphqlWsMessageTypes.connectionAck,
            orElse: () => throw StateError('WebSocket closed before receiving connection_ack'),
          )
          .catchError((_) => GraphLinkSubscriptionErrorMessage(type: GraphqlWsMessageTypes.connectionAck));
      _handshakeStatus = _HandshakeStatus.acknowledged;
      return _StreamSink(sendMessage: adapter.sendMessage, stream: _onMessageStream);
    } catch (e) {
      _handshakeStatus = _HandshakeStatus.none;
      rethrow;
    }
  }

  Future<void> _onReconnect() async {
    if (_handshakeStatus == _HandshakeStatus.progress) return;
    _handshakeStatus = _HandshakeStatus.none;
    if (_payloads.isEmpty) return;
    _sinkCompleter = Completer();
    final completer = _sinkCompleter;
    try {
      final sink = await _doHandshake();
      completer?.complete(sink);
    } catch (e) {
      completer?.completeError(e);
      _sinkCompleter = null;
      for (final uuid in _map.keys) {
        if (!_map[uuid]!.isClosed) _map[uuid]!.addError(e);
      }
    }
  }

  StreamController<Map<String, dynamic>> _createStremController(String uuid) {
    var controller = StreamController<Map<String, dynamic>>(
      onCancel: () {
        _removeController(uuid);
      },
    );
    _map[uuid] = controller;
    return controller;
  }

  Stream<Map<String, dynamic>> handle(GraphLinkPayload pl) {
    String uuid = _generateUuid();
    var controller = _createStremController(uuid);
    _payloads[uuid] = pl;

    _initWs().then((streamSink) async {
      var sub = streamSink.stream
          .map(_parseEvent)
          .where((event) => event.id == uuid)
          .listen((msg) => _handleMessage(msg, uuid));
      _subs[uuid] = sub;
      var message = GraphLinkSubscriptionMessage(
          id: uuid,
          type: GraphqlWsMessageTypes.subscribe,
          payload: GraphLinkSubscriptionPayload(
            query: pl.query,
            operationName: pl.operationName,
            variables: pl.variables,
          ));
      await streamSink.sendMessage(json.encode(message.toJson()));
    }).catchError((e) {
      if (!controller.isClosed) controller.addError(e);
      _removeController(uuid);
    });

    return controller.stream;
  }

  GraphLinkSubscriptionErrorMessageBase _parseEvent(String event) {
    var map = jsonDecode(event);
    var payload = map["payload"];
    if (payload is Map) {
      return GraphLinkSubscriptionMessage.fromJson(map);
    }
    return GraphLinkSubscriptionErrorMessage.fromJson(map);
  }

  void _handleMessage(GraphLinkSubscriptionErrorMessageBase msg, String uuid) {
    var controller = _map[uuid];
    if (controller == null) return;
    switch (msg.type!) {
      case GraphqlWsMessageTypes.ping:
        adapter.sendMessage(pongMessage);
        break;
      case GraphqlWsMessageTypes.next:
        if (!controller.isClosed) controller.add((msg as GraphLinkSubscriptionMessage).payload!.data!);
        break;
      case GraphqlWsMessageTypes.complete:
        _removeController(uuid);
        break;
      case GraphqlWsMessageTypes.error:
        var errorMsg = msg as GraphLinkSubscriptionErrorMessage;
        if (!controller.isClosed) controller.addError(errorMsg.payload as Object);
        _removeController(uuid);
        break;
      default:
    }
  }

  void _removeController(String uuid) {
    _subs.remove(uuid)?.cancel();
    _map.remove(uuid)?.close();
    _payloads.remove(uuid);
    if (_map.isEmpty) {
      _sinkCompleter = null;
    }
  }

  String _generateRandomString(int length) {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      final randomIndex = _random.nextInt(hexDigits.length);
      buffer.write(hexDigits[randomIndex]);
    }
    return buffer.toString();
  }

  String _generateUuid([String separator = "-"]) {
    return [
      _generateRandomString(8),
      _generateRandomString(4),
      _generateRandomString(4),
      _generateRandomString(4),
      _generateRandomString(12),
    ].join(separator);
  }
}

""";

const streamSink = """
class _StreamSink {
  final Future<void> Function(String) sendMessage;
  final Stream<String> stream;

  _StreamSink({required this.sendMessage, required this.stream});
}
""";

const webSocketAdapter = """
abstract class GraphLinkWebSocketAdapter {
  Future<void> connect();

  /// Must return a broadcast stream.
  Stream<String> get onMessageStream;

  Future<void> sendMessage(String message);

  Future<void> close();

  // Override to pass auth token or any connection metadata
  Future<Map<String, dynamic>?> connectionInitPayload() async => null;

  // Fires after a successful reconnect; used by the handler to re-subscribe
  Stream<void> get onReconnect => const Stream.empty();
}
""";

const defaultWebSocketAdapter = """
class DefaultGraphLinkWebSocketAdapter extends GraphLinkWebSocketAdapter {
  final String url;
  final Future<Map<String, String>?> Function()? headersProvider;
  final bool reconnect;

  WebSocketChannel? _channel;
  final _messageController = StreamController<String>.broadcast();
  final _reconnectController = StreamController<void>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _connectionCompleter;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _initialDelay = Duration(seconds: 1);
  static const Duration _maxDelay = Duration(seconds: 30);
  static final Random _random = Random();

  DefaultGraphLinkWebSocketAdapter({
    required this.url,
    this.headersProvider,
    this.reconnect = true,
  });

  @override
  Future<void> connect() async {
    await _connectOnce();
  }

  Future<void> _connectOnce() {
    if (_channel != null) return _channel!.ready;
    if (_connectionCompleter != null) return _connectionCompleter!.future;
    _connectionCompleter = Completer<void>();
    _createConnection();
    return _connectionCompleter!.future;
  }

  Future<void> _createConnection() async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _subscription = _channel!.stream.listen(
        (data) => _messageController.add(data as String),
        onError: _onError,
        onDone: _onDone,
      );
      await _channel!.ready;
      _connectionCompleter?.complete();
    } catch (e) {
      _connectionCompleter?.completeError(e);
    } finally {
      _connectionCompleter = null;
    }
  }

  void _onError(Object error) {
    if (_subscription == null) return;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (reconnect) _reconnect();
  }

  void _onDone() {
    if (_subscription == null) return;
    final closeCode = _channel?.closeCode;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (reconnect && closeCode != 1000) _reconnect();
  }

  Future<void> _reconnect() async {
    if (_reconnectAttempts >= _maxReconnectAttempts) return;
    final delay = _backoffDelay(_reconnectAttempts);
    _reconnectAttempts++;
    await Future.delayed(delay);
    await _connectOnce();
    _reconnectAttempts = 0;
    _reconnectController.add(null);
  }

  Duration _backoffDelay(int attempt) {
    final exp = min(_initialDelay.inMilliseconds * pow(2, attempt), _maxDelay.inMilliseconds);
    final jitter = _random.nextInt(1000);
    return Duration(milliseconds: exp.toInt() + jitter);
  }

  @override
  Stream<String> get onMessageStream => _messageController.stream;

  @override
  Stream<void> get onReconnect => _reconnectController.stream;

  @override
  Future<Map<String, dynamic>?> connectionInitPayload() async {
    final headers = await headersProvider?.call();
    if (headers == null || headers.isEmpty) return null;
    return headers;
  }

  @override
  Future<void> sendMessage(String message) async {
    if (_channel == null) throw StateError('WebSocket is not connected');
    _channel!.sink.add(message);
  }

  @override
  Future<void> close() async {
    _reconnectAttempts = 0;
    _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close(1000, 'normal closure');
    _channel = null;
  }
}
""";

const dartGraphqlMessageTypes = '''
class GraphqlWsMessageTypes {
  /// Client initializes connection.
  /// Example: { "type": "connection_init", "payload": { "authToken": "abc123" } }
  static const String connectionInit = 'connection_init';

  /// Server acknowledges connection.
  /// Example: { "type": "connection_ack" }
  static const String connectionAck = 'connection_ack';

  /// Client subscribes to an operation.
  /// Example:
  /// {
  ///   "id": "1",
  ///   "type": "subscribe",
  ///   "payload": { "query": "...", "variables": {} }
  /// }
  static const String subscribe = 'subscribe';

  /// Client or server pings for keep-alive.
  /// Example: { "type": "ping", "payload": {} }
  static const String ping = 'ping';

  /// Response to ping.
  /// Example: { "type": "pong" }
  static const String pong = 'pong';

  /// Server sends subscription data.
  /// Example:
  /// {
  ///   "id": "1",
  ///   "type": "next",
  ///   "payload": { "data": { "newMessage": { "id": "42", "content": "Hi" } } }
  /// }
  static const String next = 'next';

  /// Server sends a fatal error for a subscription.
  /// Example: { "id": "1", "type": "error", "payload": { "message": "Validation failed" } }
  static const String error = 'error';

  /// Client or server completes subscription.
  /// Example: { "id": "1", "type": "complete" }
  static const String complete = 'complete';
}

''';