import 'dart:async';
import 'dart:convert';

import 'package:graphlink_client_integration_tests/generated/client/graph_link_uploads.dart'
    show UploadProgressCallback;
import 'package:graphlink_client_integration_tests/generated/graphlink.dart';

/// One recorded outgoing GraphQL request.
class GraphLinkCall {
  final String? operationName;
  final Map<String, dynamic> variables;
  final String rawPayload;

  const GraphLinkCall({
    required this.operationName,
    required this.variables,
    required this.rawPayload,
  });
}

/// Drop-in adapter for [GraphLinkClient] that returns pre-registered responses
/// and records every outgoing request for assertion.
///
/// Usage:
///   final adapter = MockAdapter();
///   adapter.registerData('getUser', {'getUser': userJson});
///   final client = GraphLinkClient(adapter: adapter.call, wsAdapter: MockWebSocketAdapter());
///   // ... call client methods ...
///   expect(adapter.callCount, equals(1));
///   expect(adapter.lastCall!.variables['id'], equals('user-1'));
class MockAdapter {
  final _responses = <String, String>{};
  final _calls = <GraphLinkCall>[];

  /// Set to true to make every call throw — used for staleIfOffline tests.
  bool simulateFailure = false;

  /// Register a raw JSON string response for [operationName].
  void register(String operationName, String jsonResponse) {
    _responses[operationName] = jsonResponse;
  }

  /// Wraps [data] as `{"data": data}` and registers it.
  void registerData(String operationName, Map<String, dynamic> data) =>
      register(operationName, jsonEncode({'data': data}));

  /// Registers a GraphQL error response (data is null).
  void registerErrors(
    String operationName,
    List<Map<String, dynamic>> errors,
  ) =>
      register(operationName, jsonEncode({'data': null, 'errors': errors}));

  List<GraphLinkCall> get calls => List.unmodifiable(_calls);
  GraphLinkCall? get lastCall => _calls.isEmpty ? null : _calls.last;
  int get callCount => _calls.length;

  void reset() {
    _calls.clear();
    _responses.clear();
    simulateFailure = false;
  }

  Future<String> call(String payload) async {
    if (simulateFailure) throw Exception('Simulated network failure');

    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    final query = decoded['query'] as String? ?? '';
    final variables =
        (decoded['variables'] as Map<String, dynamic>?) ?? const {};
    final opName = _extractOperationName(query);

    _calls.add(GraphLinkCall(
      operationName: opName,
      variables: variables,
      rawPayload: payload,
    ));

    if (opName != null && _responses.containsKey(opName)) {
      return _responses[opName]!;
    }

    throw StateError(
      'MockAdapter: no response registered for "${opName ?? "unknown"}".\n'
      'Registered operations: ${_responses.keys.toList()}\n'
      'Payload: $payload',
    );
  }

  static String? _extractOperationName(String query) =>
      _parseOperationName(query);
}

String? _parseOperationName(String query) {
  final match = RegExp(r'(?:query|mutation|subscription)\s+(\w+)')
      .firstMatch(query.trim());
  return match?.group(1);
}

/// Multipart adapter for upload mutation tests.
///
/// Intercepts `GLMultipartAdapter` calls, returns pre-registered JSON
/// responses, and records the raw `parts` map for assertion.
///
/// Usage:
///   final multipart = MockMultipartAdapter();
///   multipart.registerData('uploadAvatar', {'uploadAvatar': userJson});
///   final client = GraphLinkClient(
///     adapter: adapter.call,
///     uploadAdapter: multipart.call,
///     wsAdapter: MockWebSocketAdapter(),
///   );
class MockMultipartAdapter {
  final _responses = <String, String>{};
  final _calls = <Map<String, Object>>[];

  /// Register a raw JSON string response for [operationName].
  void register(String operationName, String jsonResponse) {
    _responses[operationName] = jsonResponse;
  }

  /// Wraps [data] as `{"data": data}` and registers it.
  void registerData(String operationName, Map<String, dynamic> data) =>
      register(operationName, jsonEncode({'data': data}));

  List<Map<String, Object>> get calls => List.unmodifiable(_calls);
  Map<String, Object>? get lastCall => _calls.isEmpty ? null : _calls.last;
  int get callCount => _calls.length;

  void reset() {
    _calls.clear();
    _responses.clear();
  }

  Future<String> call(
      Map<String, Object> parts, UploadProgressCallback? onProgress) async {
    _calls.add(Map.unmodifiable(parts));
    final decoded =
        jsonDecode(parts['operations'] as String) as Map<String, dynamic>;
    final opName = _parseOperationName(decoded['query'] as String? ?? '');

    if (opName != null && _responses.containsKey(opName)) {
      return _responses[opName]!;
    }

    throw StateError(
      'MockMultipartAdapter: no response registered for "${opName ?? "unknown"}".\n'
      'Registered operations: ${_responses.keys.toList()}',
    );
  }
}

/// WebSocket adapter for tests. Automatically handles the graphql-ws
/// handshake so tests only have to push data events and assert results.
class MockWebSocketAdapter extends GraphLinkWebSocketAdapter {
  final _controller = StreamController<String>.broadcast();
  final _reconnectController = StreamController<void>.broadcast();
  final _sent = <Map<String, dynamic>>[];

  String? _subscriptionId;
  final _ready = Completer<void>();

  /// All raw messages sent by the client (connection_init, subscribe, …).
  List<Map<String, dynamic>> get sentMessages => List.unmodifiable(_sent);

  /// Completes once the client has sent the graphql-ws "subscribe" message,
  /// i.e. the subscription stream is fully wired and ready to receive events.
  Future<void> get subscriptionReady => _ready.future;

  /// Push a graphql-ws "next" event for the active subscription.
  void pushEvent(Map<String, dynamic> data) {
    _controller.add(jsonEncode({
      'id': _subscriptionId,
      'type': 'next',
      'payload': {'data': data},
    }));
  }

  /// Push a "complete" event to close the active subscription stream.
  void pushComplete() {
    _controller.add(jsonEncode({'id': _subscriptionId, 'type': 'complete'}));
  }

  /// Push a raw JSON string as if it arrived from the server.
  void push(String message) => _controller.add(message);

  /// Simulate a reconnect event.
  void reconnect() => _reconnectController.add(null);

  @override
  Future<void> connect() async {}

  @override
  Stream<String> get onMessageStream => _controller.stream;

  @override
  Stream<void> get onReconnect => _reconnectController.stream;

  @override
  Future<void> sendMessage(String message) async {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    _sent.add(decoded);
    final type = decoded['type'] as String?;
    if (type == 'connection_init') {
      // Defer the ack by one event-loop turn so that _performHandshake's
      // firstWhere listener is already attached when the ack arrives on the
      // broadcast stream.
      Future.delayed(Duration.zero, () {
        _controller.add(jsonEncode({'type': 'connection_ack'}));
      });
    } else if (type == 'subscribe') {
      _subscriptionId = decoded['id'] as String?;
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  @override
  Future<void> close() async {
    await _controller.close();
    await _reconnectController.close();
  }
}
