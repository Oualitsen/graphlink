import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/enums/user_status.dart';
import 'package:graphlink_client_integration_tests/generated/enums/priority.dart';
import 'fixtures.dart';
import 'mock_adapter.dart';

void main() {
  late MockAdapter adapter;
  late GraphLinkClient client;

  setUp(() {
    adapter = MockAdapter();
    client = GraphLinkClient(adapter: adapter.call, wsAdapter: MockWebSocketAdapter());
  });

  group('enum deserialization', () {
    test('ACTIVE deserializes to UserStatus.ACTIVE', () async {
      adapter.registerData('getUser', {'getUser': kUserAliceJson});
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser.status, equals(UserStatus.ACTIVE));
    });

    test('INACTIVE deserializes to UserStatus.INACTIVE', () async {
      adapter.registerData('getUser', {'getUser': kUserBobJson});
      final res = await client.queries.getUser(id: 'user-2');
      expect(res.getUser.status, equals(UserStatus.INACTIVE));
    });

    test('HIGH deserializes to Priority.HIGH', () async {
      adapter.registerData('getUser', {'getUser': kUserAliceJson});
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser.priority, equals(Priority.HIGH));
    });

    test('nullable enum is null when server returns null', () async {
      adapter.registerData('getUser', {'getUser': kUserBobJson});
      final res = await client.queries.getUser(id: 'user-2');
      // kUserBobJson has priority: null
      expect(res.getUser.priority, isNull);
    });
  });

  group('enum serialization in query variables', () {
    setUp(() {
      adapter.registerData('listUsersByStatus', {'listUsersByStatus': []});
    });

    test('UserStatus.ACTIVE is serialized as "ACTIVE" in variables', () async {
      await client.queries.listUsersByStatus(status: UserStatus.ACTIVE);
      expect(adapter.lastCall!.variables['status'], equals('ACTIVE'));
    });

    test('UserStatus.INACTIVE is serialized as "INACTIVE" in variables',
        () async {
      await client.queries.listUsersByStatus(status: UserStatus.INACTIVE);
      expect(adapter.lastCall!.variables['status'], equals('INACTIVE'));
    });

    test('UserStatus.SUSPENDED is serialized as "SUSPENDED" in variables',
        () async {
      await client.queries.listUsersByStatus(status: UserStatus.SUSPENDED);
      expect(adapter.lastCall!.variables['status'], equals('SUSPENDED'));
    });
  });

  group('enum in list response', () {
    test('list of users contains correctly deserialized statuses', () async {
      adapter.registerData('listUsers', {
        'listUsers': [kUserAliceJson, kUserBobJson],
      });
      final res = await client.queries.listUsers();
      expect(res.listUsers[0].status, equals(UserStatus.ACTIVE));
      expect(res.listUsers[1].status, equals(UserStatus.INACTIVE));
    });
  });
}
