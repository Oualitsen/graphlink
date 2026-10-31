import 'dart:convert';

import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'fixtures.dart';
import 'mock_adapter.dart';

void main() {
  late MockAdapter adapter;
  late GraphLinkClient client;

  setUp(() {
    adapter = MockAdapter();
    client = GraphLinkClient(adapter: adapter.call, wsAdapter: MockWebSocketAdapter());
  });

  String sentQuery() => (jsonDecode(adapter.lastCall!.rawPayload) as Map)['query'] as String;

  group('literal arguments', () {
    test('a string literal is sent inline and needs no parameter', () async {
      adapter.registerData('findFirstUser', {'findUser': kUserAliceJson});
      final res = await client.queries.findFirstUser();
      expect(res.findUser?.name, equals('Alice Smith'));
      expect(adapter.lastCall!.variables, isEmpty);
      expect(sentQuery(), contains('findUser(id: "user-1")'));
    });

    test('an enum literal is sent inline', () async {
      adapter.registerData('listActiveUsers', {'listUsersByStatus': [kUserAliceJson]});
      final res = await client.queries.listActiveUsers();
      expect(res.listUsersByStatus, hasLength(1));
      expect(adapter.lastCall!.variables, isEmpty);
      expect(sentQuery(), contains('listUsersByStatus(status: ACTIVE)'));
    });

    test('several literals in one field are sent inline', () async {
      adapter.registerData('searchAlice', {'searchUsers': [kUserAliceJson]});
      await client.queries.searchAlice();
      expect(adapter.lastCall!.variables, isEmpty);
      expect(sentQuery(), contains('searchUsers(name: "Alice",limit: 5)'));
    });

    test('a literal and a variable can be mixed', () async {
      adapter.registerData('searchWithFixedLimit', {'searchUsers': [kUserBobJson]});
      await client.queries.searchWithFixedLimit(name: 'Bob');
      expect(adapter.lastCall!.variables, equals({'name': 'Bob'}));
      expect(sentQuery(), contains(r'searchUsers(name: $name,limit: 10)'));
    });

    test('dollar signs inside a literal reach the server unchanged', () async {
      adapter.registerData('searchPrice', {'searchUsers': <Map<String, dynamic>>[]});
      await client.queries.searchPrice();
      expect(adapter.lastCall!.variables, isEmpty);
      expect(sentQuery(), contains(r'name: "cost $5 or $6"'));
    });
  });
}
