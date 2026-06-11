import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'real_server_adapter.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('non-nullable query return', () {
    test('getUser returns a non-null User', () async {
      final res = await client.queries.getUser(id: 'user-1', limit: 10);
      expect(res.getUser, isNotNull);
      expect(res.getUser.id, equals('user-1'));
    });
  });

  group('nullable query return', () {
    test('findUser returns null for unknown id', () async {
      final res = await client.queries.findUser(id: 'missing', limit: 10);
      expect(res.findUser, isNull);
    });

    test('findUser returns a User when found', () async {
      final res = await client.queries.findUser(id: 'user-1', limit: 10);
      expect(res.findUser, isNotNull);
      expect(res.findUser!.name, equals('Alice Smith'));
    });
  });

  group('nullable nested object fields', () {
    test('billingAddress is null for Alice', () async {
      final res = await client.queries.getUser(id: 'user-1', limit: 10);
      expect(res.getUser.billingAddress, isNull);
    });

    test('billingAddress is non-null for Bob', () async {
      final res = await client.queries.getUser(id: 'user-2', limit: 10);
      expect(res.getUser.billingAddress, isNotNull);
      expect(res.getUser.billingAddress!.city, equals('Capital City'));
    });

    test('coAuthor on Post is null when absent (post-1)', () async {
      final res = await client.queries.getPost(id: 'post-1');
      expect(res.getPost.coAuthor, isNull);
    });

    test('coAuthor on Post is non-null when present (post-2)', () async {
      final res = await client.queries.getPost(id: 'post-2');
      expect(res.getPost.coAuthor, isNotNull);
      expect(res.getPost.coAuthor!.id, equals('user-2'));
    });
  });

  group('nullable scalar fields on nested type', () {
    test('Address.zip is null for Bob (no zip)', () async {
      final res = await client.queries.getUser(id: 'user-2', limit: 10);
      expect(res.getUser.address.zip, isNull);
    });

    test('Address.zip has value for Alice', () async {
      final res = await client.queries.getUser(id: 'user-1', limit: 10);
      expect(res.getUser.address.zip, equals('12345'));
    });
  });

  group('nullable list fields', () {
    test('scores is null for Bob', () async {
      final res = await client.queries.getUser(id: 'user-2', limit: 10);
      expect(res.getUser.scores, isNull);
    });

    test('scores is non-null list for Alice', () async {
      final res = await client.queries.getUser(id: 'user-1', limit: 10);
      expect(res.getUser.scores, isNotNull);
      expect(res.getUser.scores, containsAll([10, 20, 30]));
    });
  });
}
