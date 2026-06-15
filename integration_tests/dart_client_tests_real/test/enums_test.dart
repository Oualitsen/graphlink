import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/enums/user_status.dart';
import 'package:graphlink_client_integration_tests/generated/enums/priority.dart';
import 'real_server_adapter.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('enum deserialization', () {
    test('ACTIVE deserializes to UserStatus.ACTIVE', () async {
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser.status, equals(UserStatus.ACTIVE));
    });

    test('INACTIVE deserializes to UserStatus.INACTIVE', () async {
      final res = await client.queries.getUser(id: 'user-2');
      expect(res.getUser.status, equals(UserStatus.INACTIVE));
    });

    test('HIGH deserializes to Priority.HIGH', () async {
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser.priority, equals(Priority.HIGH));
    });

    test('nullable enum is null when server returns null', () async {
      final res = await client.queries.getUser(id: 'user-2');
      expect(res.getUser.priority, isNull);
    });
  });

  group('enum serialization in query variables', () {
    test('UserStatus.ACTIVE filters correctly — returns only active users',
        () async {
      final res = await client.queries
          .listUsersByStatus(status: UserStatus.ACTIVE);
      expect(res.listUsersByStatus, isNotEmpty);
      expect(res.listUsersByStatus.every((u) => u.status == UserStatus.ACTIVE),
          isTrue);
    });

    test('UserStatus.INACTIVE filters correctly — returns only inactive users',
        () async {
      final res = await client.queries
          .listUsersByStatus(status: UserStatus.INACTIVE);
      expect(res.listUsersByStatus, isNotEmpty);
      expect(
          res.listUsersByStatus.every((u) => u.status == UserStatus.INACTIVE),
          isTrue);
    });

    test('UserStatus.SUSPENDED filters correctly — returns empty list',
        () async {
      final res = await client.queries
          .listUsersByStatus(status: UserStatus.SUSPENDED);
      expect(res.listUsersByStatus, isEmpty);
    });
  });

  group('enum in list response', () {
    test('list of users contains correctly deserialized statuses', () async {
      final res = await client.queries.listUsers();
      final statuses = res.listUsers.map((u) => u.status).toList();
      expect(statuses, containsAll([UserStatus.ACTIVE, UserStatus.INACTIVE]));
    });
  });
}
