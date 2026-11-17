import 'dart:convert';
import 'dart:io';
import 'package:graphlink_client_integration_tests/generated/graphlink.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

final _faultPort = int.parse(Platform.environment['WS_FAULT_PORT'] ?? '9940');
final _faultUrl = 'http://127.0.0.1:$_faultPort';

void main() {
  final users = (jsonDecode(File('../fault_server/huge_case.json').readAsStringSync()) as Map)['users'] as int;

  test('a ten megabyte response is decoded without loss', () async {
    await http.post(Uri.parse('$_faultUrl/_reset'));
    await http.post(Uri.parse('$_faultUrl/_arm?fault=huge-users'));
    final ws = DefaultGraphLinkWebSocketAdapter(url: 'ws://127.0.0.1:$_faultPort/graphql');
    final client = GraphLinkClient(
      adapter: (payload) async {
        final response = await http.post(Uri.parse('$_faultUrl/graphql'), headers: {'Content-Type': 'application/json'}, body: payload);
        return utf8.decode(response.bodyBytes);
      },
      wsAdapter: ws,
    );
    try {
      final watch = Stopwatch()..start();
      final response = await client.queries.fetchBigUsers(count: users);
      watch.stop();

      final list = response.bigUsers;
      expect(list.length, users);
      expect(list.first.id, 'user-0');
      expect(list.last.name, 'User ${users - 1} Ünï 日本');
      expect(list.last.email, 'user-${users - 1}@example.com');
      expect(list[1].status, UserStatus.inactive);
      expect(list[users ~/ 2].tags, ['alpha', 'beta']);
      expect(list.first.address.zip, isNull);
      expect(watch.elapsed, lessThan(const Duration(seconds: 30)));

      await http.post(Uri.parse('$_faultUrl/_arm?fault=huge-users'));
      expect((await client.queries.fetchBigUsers(count: users)).bigUsers.length, users);
    } finally {
      await ws.close();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
