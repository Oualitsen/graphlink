import 'package:graphlink_client_integration_tests/generated/graphlink.dart';
import 'package:test/test.dart';

import 'real_server_adapter.dart';

const _timeout = Duration(seconds: 10);

void main() {
  final adapters = <DefaultGraphLinkWebSocketAdapter>[];
  var next = 0;

  GraphLinkClient clientWith(Future<Map<String, String>?> Function()? headers) {
    final ws = DefaultGraphLinkWebSocketAdapter(
        url: 'ws://localhost:9999/graphql', headersProvider: headers);
    adapters.add(ws);
    return GraphLinkClient(adapter: realHttpAdapter, wsAdapter: ws);
  }

  tearDown(() async {
    for (final ws in adapters) {
      await ws.close();
    }
    adapters.clear();
  });

  group('connection_init payload', () {
    test('carries the token to the server', () async {
      final token = 'dart-${DateTime.now().microsecondsSinceEpoch}-${next++}';
      final client =
          clientWith(() async => {'Authorization': 'Bearer $token'});
      final events =
          await client.subscriptions.secureTicks(count: 3).toList().timeout(_timeout);
      expect(events.map((e) => e.secureTicks), [1, 2, 3]);

      final starts = await clientWith(null).queries.secureTickStarts(token: token);
      expect(starts.secureTickStarts, 1);
    });

    test('a subscription without a token fails', () async {
      final events = [];
      Object? error;
      try {
        await for (final e in clientWith(null).subscriptions.secureTicks(count: 3).timeout(_timeout)) {
          events.add(e);
        }
      } catch (e) {
        error = e;
      }
      expect(events, isEmpty);
      expect(error, isNotNull);
    });
  });
}
