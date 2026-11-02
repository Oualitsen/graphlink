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

const dartRestFile = '''
typedef GLRestAdapter = Future<RestResponse> Function(RestRequest request);

abstract class RestBody {
  const RestBody();
}

class RestJsonBody extends RestBody {
  final String json;
  const RestJsonBody(this.json);
}

class RestFormBody extends RestBody {
  final List<MapEntry<String, String>> fields;
  const RestFormBody(this.fields);
}

class RestPart {
  final String name;
  final String? value;
  final GLUpload? file;
  final String? mimeType;
  const RestPart.text(this.name, String this.value, {this.mimeType}) : file = null;
  const RestPart.file(this.name, GLUpload this.file) : value = null, mimeType = null;
}

class RestMultipartBody extends RestBody {
  final List<RestPart> parts;
  const RestMultipartBody(this.parts);
}

class RestRawBody extends RestBody {
  final GLUpload upload;
  const RestRawBody(this.upload);
}

class RestRequest {
  final String method;
  final String path;
  final List<MapEntry<String, String>> query;
  final Map<String, String> headers;
  final RestBody? body;
  final UploadProgressCallback? onSendProgress;

  const RestRequest({
    required this.method,
    required this.path,
    this.query = const [],
    this.headers = const {},
    this.body,
    this.onSendProgress,
  });
}

class RestResponse {
  final int status;
  final Map<String, String> headers;
  final Stream<List<int>> stream;

  const RestResponse({required this.status, required this.stream, this.headers = const {}});

  bool get isSuccess => status >= 200 && status < 300;

  Future<Uint8List> bytes() async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<String> text() async => utf8.decode(await bytes());

  Future<Object?> json() async {
    final body = await text();
    return body.isEmpty ? null : jsonDecode(body);
  }
}

typedef DownloadProgressCallback = void Function(int received, int total);

class GLDownload {
  final Stream<List<int>> stream;
  final String? filename;
  final String? contentType;
  final int? length;

  const GLDownload({required this.stream, this.filename, this.contentType, this.length});

  factory GLDownload.fromResponse(RestResponse response, [DownloadProgressCallback? onProgress]) {
    String? header(String name) {
      for (final entry in response.headers.entries) {
        if (entry.key.toLowerCase() == name) return entry.value;
      }
      return null;
    }

    final length = int.tryParse(header('content-length') ?? '');
    var received = 0;
    final stream = onProgress == null
        ? response.stream
        : response.stream.map((chunk) {
            received += chunk.length;
            onProgress(received, length ?? -1);
            return chunk;
          });
    final disposition = header('content-disposition');
    final match = disposition == null ? null : RegExp(r'filename\*?=(?:UTF-8\'\')?"?([^";]+)"?', caseSensitive: false).firstMatch(disposition);
    return GLDownload(
      stream: stream,
      filename: match == null ? null : Uri.decodeComponent(match.group(1)!),
      contentType: header('content-type'),
      length: length,
    );
  }

  Future<Uint8List> bytes() async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}

class RestError implements Exception {
  final int status;
  final Map<String, String> headers;
  final String body;

  const RestError({required this.status, required this.headers, required this.body});

  static Future<RestError> from(RestResponse response) async =>
      RestError(status: response.status, headers: response.headers, body: await response.text());

  @override
  String toString() => 'RestError(\$status): \$body';
}

Future<String> glNoGraphQL__(String payload, [String? operationName]) =>
    throw StateError('This schema has no GraphQL operation: pass no GraphQL adapter');

String _restText(Object value) => value is String ? value : value.toString();

void _restCollect(List<MapEntry<String, String>> out, String key, Object? value, bool bracket, bool comma, bool inList) {
  if (value == null) return;
  if (value is Map) {
    value.forEach((k, v) => _restCollect(out, bracket ? '\$key[\$k]' : '\$key.\$k', v, bracket, comma, false));
  } else if (value is List) {
    final items = value.where((e) => e != null).toList();
    if (items.isEmpty) return;
    if (!inList && items.every((e) => e is! Map && e is! List)) {
      if (comma) {
        out.add(MapEntry(key, items.map((e) => _restText(e!)).join(',')));
      } else {
        for (final e in items) {
          out.add(MapEntry(key, _restText(e!)));
        }
      }
    } else {
      for (var i = 0; i < value.length; i++) {
        _restCollect(out, bracket ? '\$key[\$i]' : '\$key.\$i', value[i], bracket, comma, true);
      }
    }
  } else {
    out.add(MapEntry(key, _restText(value)));
  }
}

List<MapEntry<String, String>> restEntries(String key, Object? value, {bool bracket = false, bool comma = false}) {
  final out = <MapEntry<String, String>>[];
  _restCollect(out, key, value, bracket, comma, false);
  return out;
}

List<MapEntry<String, String>> restSpreadEntries(Object? json, Map<String, String> names, {bool bracket = false, bool comma = false}) {
  final out = <MapEntry<String, String>>[];
  if (json is Map) {
    names.forEach((field, wire) => _restCollect(out, wire, json[field], bracket, comma, false));
  }
  return out;
}

String restHeaderValue(Object value) => value is List ? value.where((e) => e != null).map((e) => _restText(e!)).join(',') : _restText(value);

Map<String, String> restHeaders(Object? json, Map<String, String> names) {
  final out = <String, String>{};
  if (json is Map) {
    names.forEach((field, header) {
      final value = json[field];
      if (value != null) out[header] = restHeaderValue(value);
    });
  }
  return out;
}

List<RestPart> restParts(List<MapEntry<String, String>> entries) => entries.map((e) => RestPart.text(e.key, e.value)).toList();

Object? restNavigate(Object? json, List<String> path) {
  var current = json;
  for (final segment in path) {
    current = current is Map ? current[segment] : null;
  }
  return current;
}
''';

const dartRestResolver = '''
mixin GraphLinkRestResolver on GraphLinkResolverBase {
  late final GLRestAdapter restAdapter;

  Future<RestResponse> restCall__(RestRequest request) async {
    final response = await restAdapter(request);
    if (!response.isSuccess) throw await RestError.from(response);
    return response;
  }

  Future<void> restVoid__(RestRequest request) async {
    final response = await restCall__(request);
    await response.stream.drain<void>();
  }

  Future<GLDownload?> restDownload__(RestRequest request, bool allowEmpty, DownloadProgressCallback? onProgress) async {
    final response = await restCall__(request);
    if (response.status == 204) {
      await response.stream.drain<void>();
      if (allowEmpty) return null;
      throw FormatException('Empty REST response for a non-null download of \${request.method} \${request.path}');
    }
    return GLDownload.fromResponse(response, onProgress);
  }

  Future<String> restText__(RestRequest request) async => (await restCall__(request)).text();

  Future<String?> restTextOrNull__(RestRequest request) async {
    final text = await (await restCall__(request)).text();
    return text.isEmpty ? null : text;
  }

  Future<Object?> restJson__(RestRequest request, List<String> path, bool allowEmpty) async {
    final json = restNavigate(await (await restCall__(request)).json(), path);
    if (json == null && !allowEmpty) throw FormatException('Empty REST response for a non-null result of \${request.method} \${request.path}');
    return json;
  }

  Future<T> restCached__<T>(
    String name,
    Map<String, dynamic> variables,
    int ttl,
    List<String> tags,
    bool staleIfOffline,
    Future<Object?> Function() fetch,
    T Function(Object? json) decode,
  ) async {
    final key = GraphLinkPartialQuery.computeCacheKey(name, variables);
    final cached = await getFromCache(key, tags, staleIfOffline);
    if (cached != null && !cached.stale) return decode(jsonDecode(cached.data));
    Object? json;
    try {
      json = await fetch();
    } on RestError {
      rethrow;
    } catch (_) {
      if (cached != null) return decode(jsonDecode(cached.data));
      rethrow;
    }
    final value = decode(json);
    if (json != null) {
      final entry = GraphLinkCacheEntry(jsonEncode(json), DateTime.now().millisecondsSinceEpoch + ttl * 1000);
      await glStore__.set(key, jsonEncode(entry.toJson()));
      if (tags.isNotEmpty) await addKeyToTags(key, tags);
    }
    return value;
  }
}
''';

const dartRestHttpAdapter = r'''
class GraphLinkRestHttpAdapter {
  final String baseUrl;
  final Future<Map<String, String>?> Function()? headersProvider;

  GraphLinkRestHttpAdapter({required this.baseUrl, this.headersProvider});

  Future<RestResponse> call(RestRequest request) async {
    final headers = <String, String>{...?await headersProvider?.call(), ...request.headers};
    final outgoing = await _build(request, _uri(request), headers);
    final response = await outgoing.send();
    return RestResponse(status: response.statusCode, headers: response.headers, stream: response.stream);
  }

  Uri _uri(RestRequest request) {
    final base = Uri.parse(baseUrl);
    final query = request.query.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
    final path = base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path;
    return base.replace(path: '$path${request.path}', query: query.isEmpty ? null : query);
  }

  Future<http.BaseRequest> _build(RestRequest request, Uri uri, Map<String, String> headers) async {
    final body = request.body;
    if (body is RestMultipartBody) return _multipart(request, body, uri, headers);
    if (body is RestRawBody) return _raw(request, body, uri, headers);
    final outgoing = http.Request(request.method, uri)..headers.addAll(headers);
    if (body is RestJsonBody) outgoing.body = body.json;
    if (body is RestFormBody) {
      outgoing.body = body.fields.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
    }
    return outgoing;
  }

  Future<http.BaseRequest> _multipart(RestRequest request, RestMultipartBody body, Uri uri, Map<String, String> headers) async {
    final outgoing = http.MultipartRequest(request.method, uri)..headers.addAll(headers);
    for (final part in body.parts) {
      final file = part.file;
      if (file == null) {
        final mimeType = part.mimeType;
        outgoing.files.add(http.MultipartFile.fromString(part.name, part.value!,
            contentType: mimeType == null ? null : MediaType.parse(mimeType)));
      } else {
        final length = file.length;
        final contentType = MediaType.parse(file.mimeType);
        outgoing.files.add(length == null
            ? http.MultipartFile.fromBytes(part.name, await _readAll(file.stream), filename: file.filename, contentType: contentType)
            : http.MultipartFile(part.name, file.stream, length, filename: file.filename, contentType: contentType));
      }
    }
    final onProgress = request.onSendProgress;
    if (onProgress == null) return outgoing;
    final bytes = await outgoing.finalize().toBytes();
    final counted = http.StreamedRequest(request.method, uri)
      ..headers.addAll(headers)
      ..headers['content-type'] = outgoing.headers['content-type']!
      ..contentLength = bytes.length;
    const chunkSize = 8192;
    final chunks = [
      for (var i = 0; i < bytes.length; i += chunkSize) bytes.sublist(i, i + chunkSize > bytes.length ? bytes.length : i + chunkSize),
    ];
    _pipe(counted, Stream.fromIterable(chunks), bytes.length, onProgress);
    return counted;
  }

  http.BaseRequest _raw(RestRequest request, RestRawBody body, Uri uri, Map<String, String> headers) {
    final outgoing = http.StreamedRequest(request.method, uri)..headers.addAll(headers);
    final length = body.upload.length;
    if (length != null) outgoing.contentLength = length;
    _pipe(outgoing, body.upload.stream, length, request.onSendProgress);
    return outgoing;
  }

  void _pipe(http.StreamedRequest outgoing, Stream<List<int>> source, int? total, UploadProgressCallback? onProgress) {
    var sent = 0;
    source.listen(
      (chunk) {
        sent += chunk.length;
        outgoing.sink.add(chunk);
        onProgress?.call(sent, total ?? -1);
      },
      onError: outgoing.sink.addError,
      onDone: outgoing.sink.close,
      cancelOnError: true,
    );
  }

  Future<List<int>> _readAll(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
''';

const dartRestDioAdapter = r'''
class GraphLinkRestDioAdapter {
  final String baseUrl;
  final Dio dio;
  final Future<Map<String, String>?> Function()? headersProvider;

  GraphLinkRestDioAdapter({required this.baseUrl, Dio? dio, this.headersProvider}) : dio = dio ?? Dio();

  Future<RestResponse> call(RestRequest request) async {
    final headers = <String, String>{...?await headersProvider?.call(), ...request.headers};
    final body = request.body;
    final upload = body is RestRawBody ? body.upload : null;
    if (upload?.length != null) headers['Content-Length'] = '${upload!.length}';
    final response = await dio.request<ResponseBody>(
      _uri(request).toString(),
      data: await _data(body, request.onSendProgress),
      options: Options(
        method: request.method,
        headers: headers,
        responseType: ResponseType.stream,
        validateStatus: (_) => true,
      ),
      onSendProgress: body is RestMultipartBody ? request.onSendProgress : null,
    );
    return RestResponse(
      status: response.statusCode ?? 0,
      headers: {for (final e in response.headers.map.entries) e.key: e.value.join(',')},
      stream: response.data!.stream,
    );
  }

  Uri _uri(RestRequest request) {
    final base = Uri.parse(baseUrl);
    final query = request.query.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
    final path = base.path.endsWith('/') ? base.path.substring(0, base.path.length - 1) : base.path;
    return base.replace(path: '$path${request.path}', query: query.isEmpty ? null : query);
  }

  Future<Object?> _data(RestBody? body, UploadProgressCallback? onProgress) async {
    if (body is RestJsonBody) return body.json;
    if (body is RestFormBody) {
      return body.fields.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
    }
    if (body is RestRawBody) return _counted(body.upload.stream, body.upload.length, onProgress);
    if (body is RestMultipartBody) return _form(body);
    return null;
  }

  Stream<List<int>> _counted(Stream<List<int>> source, int? total, UploadProgressCallback? onProgress) {
    if (onProgress == null) return source;
    var sent = 0;
    return source.map((chunk) {
      sent += chunk.length;
      onProgress(sent, total ?? -1);
      return chunk;
    });
  }

  Future<FormData> _form(RestMultipartBody body) async {
    final form = FormData();
    for (final part in body.parts) {
      final file = part.file;
      if (file == null) {
        final mimeType = part.mimeType;
        if (mimeType == null) {
          form.fields.add(MapEntry(part.name, part.value!));
        } else {
          form.files.add(MapEntry(part.name, MultipartFile.fromString(part.value!, contentType: MediaType.parse(mimeType))));
        }
      } else {
        final length = file.length;
        final contentType = MediaType.parse(file.mimeType);
        form.files.add(MapEntry(
          part.name,
          length == null
              ? MultipartFile.fromBytes(await _readAll(file.stream), filename: file.filename, contentType: contentType)
              : MultipartFile.fromStream(() => file.stream, length, filename: file.filename, contentType: contentType),
        ));
      }
    }
    return form;
  }

  Future<List<int>> _readAll(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
''';
