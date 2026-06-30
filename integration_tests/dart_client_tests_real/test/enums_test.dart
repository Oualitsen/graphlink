import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/enums/user_status.dart';
import 'package:graphlink_client_integration_tests/generated/enums/priority.dart';
import 'real_server_adapter.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('enum deserialization', () {
    test('ACTIVE deserializes to UserStatus.active', () async {
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser.status, equals(UserStatus.active));
    });

    test('INACTIVE deserializes to UserStatus.inactive', () async {
      final res = await client.queries.getUser(id: 'user-2');
      expect(res.getUser.status, equals(UserStatus.inactive));
    });

    test('HIGH deserializes to Priority.high', () async {
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser.priority, equals(Priority.high));
    });

    test('nullable enum is null when server returns null', () async {
      final res = await client.queries.getUser(id: 'user-2');
      expect(res.getUser.priority, isNull);
    });
  });

  group('enum serialization in query variables', () {
    test('UserStatus.active filters correctly — returns only active users',
        () async {
      final res = await client.queries
          .listUsersByStatus(status: UserStatus.active);
      expect(res.listUsersByStatus, isNotEmpty);
      expect(res.listUsersByStatus.every((u) => u.status == UserStatus.active),
          isTrue);
    });

    test('UserStatus.inactive filters correctly — returns only inactive users',
        () async {
      final res = await client.queries
          .listUsersByStatus(status: UserStatus.inactive);
      expect(res.listUsersByStatus, isNotEmpty);
      expect(
          res.listUsersByStatus.every((u) => u.status == UserStatus.inactive),
          isTrue);
    });

    test('UserStatus.SUSPENDED filters correctly — returns empty list',
        () async {
      final res = await client.queries
          .listUsersByStatus(status: UserStatus.suspended);
      expect(res.listUsersByStatus, isEmpty);
    });
  });

  group('enum in list response', () {
    test('list of users contains correctly deserialized statuses', () async {
      final res = await client.queries.listUsers();
      final statuses = res.listUsers.map((u) => u.status).toList();
      expect(statuses, containsAll([UserStatus.active, UserStatus.inactive]));
    });
  });
}
