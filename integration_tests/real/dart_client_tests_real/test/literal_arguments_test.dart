import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'real_server_adapter.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('literal arguments against the real server', () {
    test('a string literal selects the right user', () async {
      final res = await client.queries.findFirstUser();
      expect(res.findUser?.name, equals('Alice Smith'));
      expect(res.findUser?.email, equals('alice@test.com'));
    });

    test('an enum literal filters on the server', () async {
      final res = await client.queries.listActiveUsers();
      expect(res.listUsersByStatus.map((u) => u.id), equals(['user-1']));
    });

    test('several literals in one field are applied', () async {
      final res = await client.queries.searchAlice();
      expect(res.searchUsers.map((u) => u.name), equals(['Alice Smith']));
    });

    test('an inline limit is enforced while the other argument stays a variable', () async {
      final res = await client.queries.searchWithFixedLimit(name: 's');
      expect(res.searchUsers, hasLength(1));
    });

    test('dollar signs inside a literal form a valid query', () async {
      final res = await client.queries.searchPrice();
      expect(res.searchUsers, isEmpty);
    });
  });
}
