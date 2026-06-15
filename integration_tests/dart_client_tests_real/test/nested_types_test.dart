import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'real_server_adapter.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('required nested object', () {
    test('User.address is correctly deserialized', () async {
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser.address.street, equals('123 Main St'));
      expect(res.getUser.address.city, equals('Springfield'));
      expect(res.getUser.address.country, equals('US'));
      expect(res.getUser.address.zip, equals('12345'));
    });
  });

  group('nullable nested object', () {
    test('User.billingAddress is null for Alice', () async {
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser.billingAddress, isNull);
    });

    test('User.billingAddress is correctly deserialized for Bob', () async {
      final res = await client.queries.getUser(id: 'user-2');
      expect(res.getUser.billingAddress, isNotNull);
      expect(res.getUser.billingAddress!.street, equals('789 Pine Rd'));
      expect(res.getUser.billingAddress!.city, equals('Capital City'));
      expect(res.getUser.billingAddress!.zip, equals('99999'));
    });
  });

  group('multi-level nesting (Post → User → Address)', () {
    test('Post.author is deserialized as a full User', () async {
      final res = await client.queries.getPost(id: 'post-1');
      expect(res.getPost.author.id, equals('user-1'));
      expect(res.getPost.author.name, equals('Alice Smith'));
      expect(res.getPost.author.email, equals('alice@test.com'));
    });

    test('Post.author.address is accessible at three levels deep', () async {
      final res = await client.queries.getPost(id: 'post-1');
      expect(res.getPost.author.address.city, equals('Springfield'));
    });

    test('Post.coAuthor is null for post-1', () async {
      final res = await client.queries.getPost(id: 'post-1');
      expect(res.getPost.coAuthor, isNull);
    });

    test('Post scalar fields are deserialized correctly', () async {
      final res = await client.queries.getPost(id: 'post-1');
      expect(res.getPost.title, equals('Hello World'));
      expect(res.getPost.viewCount, equals(128));
    });
  });

  group('@glSkipOnClient — server field excluded from client type', () {
    test('AuditEntry.internalNote is not in the generated class', () async {
      // Server returns internalNote — client silently ignores it.
      final res = await client.queries.getAuditEntry(id: 'audit-2');
      expect(res.getAuditEntry.id, equals('audit-2'));
      expect(res.getAuditEntry.action, equals('LOGOUT'));
      // Compile-time assertion: res.getAuditEntry.internalNote does not exist.
    });
  });
}
