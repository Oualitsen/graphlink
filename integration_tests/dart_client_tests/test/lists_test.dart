import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/enums/user_status.dart';
import 'fixtures.dart';
import 'mock_adapter.dart';

void main() {
  late MockAdapter adapter;
  late GraphLinkClient client;

  setUp(() {
    adapter = MockAdapter();
    client = GraphLinkClient(adapter: adapter.call, wsAdapter: MockWebSocketAdapter());
  });

  group('non-nullable list of objects', () {
    test('listUsers returns a correctly typed list', () async {
      adapter.registerData('listUsers', {
        'listUsers': [kUserAliceJson, kUserBobJson],
      });
      final res = await client.queries.listUsers();
      expect(res.listUsers.length, equals(2));
      expect(res.listUsers[0].id, equals('user-1'));
      expect(res.listUsers[1].id, equals('user-2'));
    });

    test('empty list is returned as empty list, not null', () async {
      adapter.registerData('listUsers', {'listUsers': []});
      final res = await client.queries.listUsers();
      expect(res.listUsers, isNotNull);
      expect(res.listUsers, isEmpty);
    });

    test('each item in the list is fully deserialized', () async {
      adapter.registerData('listUsers', {
        'listUsers': [kUserAliceJson],
      });
      final res = await client.queries.listUsers();
      final user = res.listUsers.first;
      expect(user.name, equals('Alice Smith'));
      expect(user.address.city, equals('Springfield'));
    });
  });

  group('list of scalars on a type', () {
    test('User.tags list deserializes correctly', () async {
      adapter.registerData('getUser', {'getUser': kUserAliceJson});
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser.tags, equals(['admin', 'beta']));
    });

    test('empty tags list is empty, not null', () async {
      adapter.registerData('getUser', {'getUser': kUserBobJson});
      final res = await client.queries.getUser(id: 'user-2');
      expect(res.getUser.tags, isEmpty);
    });

    test('nullable scores list is null when server returns null', () async {
      adapter.registerData('getUser', {'getUser': kUserBobJson});
      final res = await client.queries.getUser(id: 'user-2');
      expect(res.getUser.scores, isNull);
    });

    test('nullable scores list has values when server returns them', () async {
      adapter.registerData('getUser', {'getUser': kUserAliceJson});
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser.scores, equals([10, 20, 30]));
    });
  });

  group('list of objects with nullable fields', () {
    test('getTags returns tags with nullable color', () async {
      adapter.registerData('getTags', {'getTags': kTagsJson});
      final res = await client.queries.getTags();
      expect(res.getTags.length, equals(2));
      expect(res.getTags[0].label, equals('dart'));
      expect(res.getTags[0].color, equals('#0175C2'));
      expect(res.getTags[1].color, isNull);
    });
  });

  group('list query with enum argument', () {
    test('listUsersByStatus sends enum as string variable', () async {
      adapter.registerData('listUsersByStatus', {'listUsersByStatus': []});
      await client.queries.listUsersByStatus(status: UserStatus.ACTIVE);
      expect(adapter.lastCall!.variables['status'], equals('ACTIVE'));
    });
  });
}
