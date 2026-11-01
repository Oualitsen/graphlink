import 'package:graphlink/src/persisted_queries.dart';

const handshakeStatus = """
enum GraphLinkHandshakeStatus { none, progress, acknowledged }
""";

const subscriptionHandler = """
class GraphLinkSubscriptionHandler {
  static const hexDigits = '0123456789abcdef';
  final _random = Random();
  final Map<String, StreamController<Map<String, dynamic>>> _map = {};
  final Map<String, StreamSubscription> _subs = {};
  final Map<String, GraphLinkPayload> _payloads = {};
  final GraphLinkWebSocketAdapter adapter;

  final pongMessage = jsonEncode(GraphLinkSubscriptionErrorMessage(type: GraphqlWsMessageTypes.pong).toJson());

  GraphLinkSubscriptionHandler(this.adapter) {
    adapter.onReconnect.listen((_) => _onReconnect());
  }

  Completer<GraphLinkStreamSink>? _sinkCompleter;
  GraphLinkHandshakeStatus _handshakeStatus = GraphLinkHandshakeStatus.none;
  Completer<GraphLinkStreamSink>? _handshakeCompleter;

  late final _onMessageStream = adapter.onMessageStream;

  Future<GraphLinkStreamSink> _initWs() {
    if (_sinkCompleter != null) return _sinkCompleter!.future;
    _sinkCompleter = Completer();
    _connect();
    return _sinkCompleter!.future;
  }

  Future<void> _connect() async {
    final completer = _sinkCompleter;
    try {
      await adapter.connect();
      if (_handshakeStatus == GraphLinkHandshakeStatus.acknowledged) {
        completer?.complete(GraphLinkStreamSink(sendMessage: adapter.sendMessage, stream: _onMessageStream));
      } else {
        completer?.complete(await _doHandshake());
      }
    } catch (e) {
      completer?.completeError(e);
      _sinkCompleter = null;
    }
  }

  Future<GraphLinkStreamSink> _doHandshake() {
    if (_handshakeCompleter != null) return _handshakeCompleter!.future;
    _handshakeCompleter = Completer();
    _handshakeStatus = GraphLinkHandshakeStatus.progress;
    _performHandshake().then((sink) {
      _handshakeCompleter?.complete(sink);
      _handshakeCompleter = null;
    }).catchError((e) {
      _handshakeCompleter?.completeError(e);
      _handshakeCompleter = null;
    });
    return _handshakeCompleter!.future;
  }

  Future<GraphLinkStreamSink> _performHandshake() async {
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
      _handshakeStatus = GraphLinkHandshakeStatus.acknowledged;
      return GraphLinkStreamSink(sendMessage: adapter.sendMessage, stream: _onMessageStream);
    } catch (e) {
      _handshakeStatus = GraphLinkHandshakeStatus.none;
      rethrow;
    }
  }

  Future<void> _onReconnect() async {
    if (_handshakeStatus == GraphLinkHandshakeStatus.progress) return;
    _handshakeStatus = GraphLinkHandshakeStatus.none;
    if (_payloads.isEmpty) return;
    _sinkCompleter = Completer();
    final completer = _sinkCompleter;
    try {
      final sink = await _doHandshake();
      completer?.complete(sink);
      for (final entry in _payloads.entries) {
        final id = entry.key;
        // Listener may have been cancelled when the initial connection failed;
        // re-establish it so incoming events reach the stream controller.
        if (!_subs.containsKey(id)) {
          final sub = sink.stream
              .map(_parseEvent)
              .where((event) => event.id == id)
              .listen((msg) => _handleMessage(msg, id));
          _subs[id] = sub;
        }
        final msg = GraphLinkSubscriptionMessage(
            id: id,
            type: GraphqlWsMessageTypes.subscribe,
            payload: GraphLinkSubscriptionPayload(
              query: entry.value.query,
              operationName: entry.value.operationName,
              variables: entry.value.variables,
            ));
        await sink.sendMessage(json.encode(msg.toJson()));
      }
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
      _subs.remove(uuid)?.cancel();
      // Keep _payloads[uuid] and _map[uuid] alive — _onReconnect will
      // re-establish the listener and re-send the subscribe message.
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

const dartStreamSink = """
class GraphLinkStreamSink {
  final Future<void> Function(String) sendMessage;
  final Stream<String> stream;

  GraphLinkStreamSink({required this.sendMessage, required this.stream});
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
  final List<String>? protocols;

  final int? maxReconnectAttempts;
  final Duration maxReconnectDelay;

  WebSocketChannel? _channel;
  final _messageController = StreamController<String>.broadcast();
  final _reconnectController = StreamController<void>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  Completer<void>? _connectionCompleter;
  int _reconnectAttempts = 0;
  bool _reconnecting = false;
  bool _disposed = false;
  static const Duration _initialDelay = Duration(seconds: 1);
  static final Random _random = Random();

  DefaultGraphLinkWebSocketAdapter({
    required this.url,
    this.headersProvider,
    this.reconnect = true,
    this.protocols = const ['graphql-transport-ws'],
    this.maxReconnectAttempts = 10,
    this.maxReconnectDelay = const Duration(seconds: 30),
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
      _channel = WebSocketChannel.connect(Uri.parse(url), protocols: protocols);
      _subscription = _channel!.stream.listen(
        (data) => _messageController.add(data as String),
        onError: _onError,
        onDone: _onDone,
      );
      await _channel!.ready;
      _connectionCompleter?.complete();
    } catch (e) {
      _subscription?.cancel();
      _subscription = null;
      _channel = null;
      _connectionCompleter?.completeError(e);
      // Unify initial-failure with live-drop: trigger reconnect so the handler's
      // _onReconnect fires and re-subscribes once the server comes up.
      if (reconnect && !_reconnecting && !_disposed) _reconnect();
    } finally {
      _connectionCompleter = null;
    }
  }

  void _onError(Object error) {
    if (_subscription == null) return;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (reconnect && !_reconnecting && !_disposed) _reconnect();
  }

  void _onDone() {
    if (_subscription == null) return;
    final closeCode = _channel?.closeCode;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (reconnect && closeCode != 1000 && !_reconnecting && !_disposed) _reconnect();
  }

  Future<void> _reconnect() async {
    final cap = maxReconnectAttempts;
    _reconnecting = true;
    try {
      while (!_disposed && (cap == null || _reconnectAttempts < cap)) {
        final delay = _backoffDelay(_reconnectAttempts);
        _reconnectAttempts++;
        await Future.delayed(delay);
        if (_disposed) break;
        try {
          await _connectOnce();
          _reconnectAttempts = 0;
          _reconnectController.add(null);
          return;
        } catch (e) {
          // retry
        }
      }
    } finally {
      _reconnecting = false;
    }
  }

  Duration _backoffDelay(int attempt) {
    final exp = min(_initialDelay.inMilliseconds * pow(2, attempt), maxReconnectDelay.inMilliseconds);
    final jitter = _random.nextInt(1000);
    return Duration(milliseconds: exp.toInt() + jitter);
  }

  int get reconnectAttempts => _reconnectAttempts;

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
    _disposed = true;
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
const dartSha256 = """
class GraphLinkSha256 {
  GraphLinkSha256._();

  static const List<int> _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF;

  static String hex(String input) {
    final data = utf8.encode(input);
    final bitLength = data.length * 8;
    final bytes = List<int>.filled(((data.length + 9 + 63) ~/ 64) * 64, 0);
    bytes.setRange(0, data.length, data);
    bytes[data.length] = 0x80;
    final end = bytes.length;
    bytes[end - 8] = (bitLength ~/ 0x100000000 >> 24) & 0xFF;
    bytes[end - 7] = (bitLength ~/ 0x100000000 >> 16) & 0xFF;
    bytes[end - 6] = (bitLength ~/ 0x100000000 >> 8) & 0xFF;
    bytes[end - 5] = (bitLength ~/ 0x100000000) & 0xFF;
    bytes[end - 4] = (bitLength >> 24) & 0xFF;
    bytes[end - 3] = (bitLength >> 16) & 0xFF;
    bytes[end - 2] = (bitLength >> 8) & 0xFF;
    bytes[end - 1] = bitLength & 0xFF;

    final state = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    final w = List<int>.filled(64, 0);
    for (var offset = 0; offset < bytes.length; offset += 64) {
      for (var i = 0; i < 16; i++) {
        final j = offset + i * 4;
        w[i] = (bytes[j] << 24) | (bytes[j + 1] << 16) | (bytes[j + 2] << 8) | bytes[j + 3];
      }
      for (var i = 16; i < 64; i++) {
        final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF;
      }
      var a = state[0], b = state[1], c = state[2], d = state[3];
      var e = state[4], f = state[5], g = state[6], h = state[7];
      for (var i = 0; i < 64; i++) {
        final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
        final ch = (e & f) ^ ((~e & 0xFFFFFFFF) & g);
        final t1 = (h + s1 + ch + _k[i] + w[i]) & 0xFFFFFFFF;
        final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final t2 = (s0 + maj) & 0xFFFFFFFF;
        h = g;
        g = f;
        f = e;
        e = (d + t1) & 0xFFFFFFFF;
        d = c;
        c = b;
        b = a;
        a = (t1 + t2) & 0xFFFFFFFF;
      }
      final working = [a, b, c, d, e, f, g, h];
      for (var i = 0; i < 8; i++) {
        state[i] = (state[i] + working[i]) & 0xFFFFFFFF;
      }
    }
    return state.map((v) => v.toRadixString(16).padLeft(8, '0')).join();
  }
}
""";

const dartPersistedQueries = """
class GraphLinkPersistedQueries {
  GraphLinkPersistedQueries._();

  static const int minQueryLength = ${persistedQueryMinLength};
  static const String notFound = 'PersistedQueryNotFound';
  static const String notSupported = 'PersistedQueryNotSupported';

  static Map<String, dynamic> extensions(String hash) => {
        'persistedQuery': {'version': 1, 'sha256Hash': hash},
      };

  static String? failure(String response) {
    if (!response.contains('PersistedQuery') && !response.contains('PERSISTED_QUERY')) return null;
    final decoded = jsonDecode(response);
    final errors = decoded is Map ? decoded['errors'] : null;
    if (errors is! List) return null;
    for (final error in errors) {
      if (error is! Map) continue;
      final details = error['extensions'];
      final code = details is Map ? details['code'] : null;
      if (error['message'] == notFound || code == 'PERSISTED_QUERY_NOT_FOUND') return notFound;
      if (error['message'] == notSupported || code == 'PERSISTED_QUERY_NOT_SUPPORTED') return notSupported;
    }
    return null;
  }
}
""";

const dartPersistedQueriesGet = """
class GraphLinkGetNotSupported implements Exception {
  final String? message;

  const GraphLinkGetNotSupported([this.message]);

  @override
  String toString() => message == null ? 'GraphLinkGetNotSupported' : 'GraphLinkGetNotSupported: ' + message!;
}

class GraphLinkGetRequest {
  GraphLinkGetRequest._();

  static Map<String, String> queryParameters(String payload) {
    final body = jsonDecode(payload) as Map<String, dynamic>;
    final variables = body['variables'];
    return {
      if (body['operationName'] != null) 'operationName': body['operationName'] as String,
      if (variables is Map && variables.isNotEmpty) 'variables': jsonEncode(variables),
      'extensions': jsonEncode(body['extensions']),
    };
  }
}
""";
