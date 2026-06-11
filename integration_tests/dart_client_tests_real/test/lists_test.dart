import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/enums/user_status.dart';
import 'real_server_adapter.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('non-nullable list of objects', () {
    test('listUsers returns a correctly typed list with 2 users', () async {
      final res = await client.queries.listUsers(limit: 10);
      expect(res.listUsers.length, equals(2));
      expect(res.listUsers[0].id, equals('user-1'));
      expect(res.listUsers[1].id, equals('user-2'));
    });

    test('each item in the list is fully deserialized', () async {
      final res = await client.queries.listUsers(limit: 10);
      final user = res.listUsers.first;
      expect(user.name, equals('Alice Smith'));
      expect(user.address.city, equals('Springfield'));
    });
  });

  group('list of scalars on a type', () {
    test('User.tags list deserializes correctly for Alice', () async {
      final res = await client.queries.getUser(id: 'user-1', limit: 10);
      expect(res.getUser.tags, equals(['admin', 'beta']));
    });

    test('empty tags list is empty for Bob', () async {
      final res = await client.queries.getUser(id: 'user-2', limit: 10);
      expect(res.getUser.tags, isEmpty);
    });

    test('nullable scores list is null for Bob', () async {
      final res = await client.queries.getUser(id: 'user-2', limit: 10);
      expect(res.getUser.scores, isNull);
    });

    test('nullable scores list has values for Alice', () async {
      final res = await client.queries.getUser(id: 'user-1', limit: 10);
      expect(res.getUser.scores, equals([10, 20, 30]));
    });
  });

  group('list of objects with nullable fields', () {
    test('getTags returns tags with nullable color', () async {
      final res = await client.queries.getTags();
      expect(res.getTags.length, equals(2));
      expect(res.getTags[0].label, equals('dart'));
      expect(res.getTags[0].color, equals('#0175C2'));
      expect(res.getTags[1].color, isNull);
    });
  });

  group('list query with enum argument', () {
    test('listUsersByStatus(ACTIVE) returns only active users', () async {
      final res = await client.queries
          .listUsersByStatus(status: UserStatus.ACTIVE, limit: 10);
      expect(res.listUsersByStatus, isNotEmpty);
      expect(res.listUsersByStatus.first.status, equals(UserStatus.ACTIVE));
    });
  });
}
