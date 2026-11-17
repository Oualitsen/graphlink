import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:graphlink_client_integration_tests/generated/graphlink.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

final _faultPort = int.parse(Platform.environment['WS_FAULT_PORT'] ?? '9940');
final _faultUrl = 'http://127.0.0.1:$_faultPort';

const _knownDefects = <String, String>{};

Future<List<String>> _framesSent() async {
  final log = jsonDecode((await http.get(Uri.parse('$_faultUrl/_ws_log'))).body) as List<dynamic>;
  return [
    for (final connection in log)
      for (final frame in (connection as Map)['frames'] as List<dynamic>) (frame as Map)['type'] as String,
  ];
}

Future<int> _connections() async =>
    (jsonDecode((await http.get(Uri.parse('$_faultUrl/_ws_log'))).body) as List<dynamic>).length;

void main() {
  final cases = (jsonDecode(File('../fault_server/ws_cases.json').readAsStringSync()) as List<dynamic>)
      .cast<Map<String, dynamic>>();

  for (final c in cases) {
    final fault = c['fault'] as String;
    test(fault, () async {
      await http.post(Uri.parse('$_faultUrl/_reset'));
      await http.post(Uri.parse('$_faultUrl/_arm?fault=$fault&times=${c['times'] ?? 1}'));
      final ws = DefaultGraphLinkWebSocketAdapter(url: 'ws://127.0.0.1:$_faultPort/graphql');
      final client = GraphLinkClient(
        adapter: (payload) async => (await http.post(Uri.parse('$_faultUrl/graphql'), body: payload)).body,
        wsAdapter: ws,
      );
      final events = <int>[];
      Object? error;
      var settled = false;
      final subscription = client.subscriptions.counterTick().listen(
            (e) => events.add(e.counterTick),
            onError: (Object e) {
              error = e;
              settled = true;
            },
            onDone: () => settled = true,
          );
      final deadline = DateTime.now().add(Duration(seconds: (c['waitSeconds'] as int?) ?? 8));
      while (!settled && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      await subscription.cancel();
      final sent = await _framesSent();
      final connections = await _connections();
      await ws.close();

      if (c['waitSeconds'] == null) {
        expect(settled, isTrue, reason: 'the subscription hung');
        switch (c['expect']) {
          case 'value':
            expect(error, isNull);
            expect(events, [1]);
            break;
          case 'error':
            expect(error, isNotNull, reason: 'no failure, events=$events');
            if (c['message'] != null) {
              final failure = error;
              final text = failure is List ? failure.map((e) => (e as dynamic).message).join() : '$failure';
              expect(text, contains(c['message'] as String));
            }
            break;
        }
      }
      if (c['noSubscribeBeforeAck'] == true) expect(sent, isNot(contains('subscribe')));
      if (c['pong'] == true) expect(sent, contains('pong'));
      if (c['maxConnections'] != null) expect(connections, lessThanOrEqualTo(c['maxConnections'] as int));
      if (c['minConnections'] != null) expect(connections, greaterThanOrEqualTo(c['minConnections'] as int));
    }, timeout: const Timeout(Duration(seconds: 40)), skip: _knownDefects[fault]);
  }
}
