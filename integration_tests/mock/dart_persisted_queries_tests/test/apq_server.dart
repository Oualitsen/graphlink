import 'dart:async';
import 'dart:convert';

import 'package:graphlink_persisted_queries_tests/generated/graphlink.dart';

class NoWebSocketAdapter extends GraphLinkWebSocketAdapter {
  @override
  Future<void> connect() async {}

  @override
  Stream<String> get onMessageStream => const Stream.empty();

  @override
  Future<void> sendMessage(String message) async {}

  @override
  Future<void> close() async {}
}

/// Behaves like an Apollo-style APQ server in front of canned responses:
/// remembers the hashes it has been told about, can forget them, and can
/// pretend APQ is switched off.
class ApqServer {
  final Map<String, Object> _responses = {};
  final Set<String> _registered = {};
  final List<Map<String, dynamic>> requests = [];

  final List<String> methods = [];

  bool supported = true;
  bool getSupported = true;
  Object? failWith;
  Object? getFailWith;

  void respondTo(String operationName, Map<String, dynamic> data) =>
      _responses[operationName] = {'data': data};

  void respondWithErrors(String operationName, List<Map<String, dynamic>> errors) =>
      _responses[operationName] = {'data': null, 'errors': errors};

  void evict() => _registered.clear();

  int get registeredCount => _registered.length;

  bool isHashOnly(Map<String, dynamic> body) => body.containsKey('extensions') && !body.containsKey('query');

  Future<String> call(String payload) {
    methods.add('POST');
    return _handle(payload, failWith);
  }

  Future<String> get(String payload) {
    methods.add('GET');
    if (!getSupported) throw const GraphLinkGetNotSupported('GET is not allowed');
    return _handle(payload, getFailWith);
  }

  Future<String> _handle(String payload, Object? failure) async {
    final body = jsonDecode(payload) as Map<String, dynamic>;
    requests.add(body);
    if (failure != null) throw failure;

    final persisted = (body['extensions'] as Map?)?['persistedQuery'] as Map?;
    if (persisted != null) {
      if (!supported) return _error('PersistedQueryNotSupported', 'PERSISTED_QUERY_NOT_SUPPORTED');
      final hash = persisted['sha256Hash'] as String;
      final query = body['query'] as String?;
      if (query == null) {
        if (!_registered.contains(hash)) return _error('PersistedQueryNotFound', 'PERSISTED_QUERY_NOT_FOUND');
      } else {
        if (GraphLinkSha256.hex(query) != hash) return _error('provided sha does not match query', 'INTERNAL_SERVER_ERROR');
        _registered.add(hash);
      }
    }
    final operationName = body['operationName'] as String;
    final response = _responses[operationName];
    if (response == null) throw StateError('No response registered for $operationName');
    return jsonEncode(response);
  }

  String _error(String message, String code) => jsonEncode({
        'errors': [
          {'message': message, 'extensions': {'code': code}},
        ],
      });
}
