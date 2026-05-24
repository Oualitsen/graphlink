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

  group('required nested object', () {
    test('User.address is correctly deserialized', () async {
      adapter.registerData('getUser', {'getUser': kUserAliceJson});
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser.address.street, equals('123 Main St'));
      expect(res.getUser.address.city, equals('Springfield'));
      expect(res.getUser.address.country, equals('US'));
      expect(res.getUser.address.zip, equals('12345'));
    });
  });

  group('nullable nested object', () {
    test('User.billingAddress is null when server returns null', () async {
      adapter.registerData('getUser', {'getUser': kUserAliceJson});
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser.billingAddress, isNull);
    });

    test('User.billingAddress is correctly deserialized when present', () async {
      adapter.registerData('getUser', {'getUser': kUserBobJson});
      final res = await client.queries.getUser(id: 'user-2');
      expect(res.getUser.billingAddress, isNotNull);
      expect(res.getUser.billingAddress!.street, equals('789 Pine Rd'));
      expect(res.getUser.billingAddress!.city, equals('Capital City'));
      expect(res.getUser.billingAddress!.zip, equals('99999'));
    });
  });

  group('multi-level nesting (Post → User → Address)', () {
    setUp(() {
      adapter.registerData('getPost', {'getPost': kPostJson});
    });

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

    test('Post.coAuthor is null when absent', () async {
      final res = await client.queries.getPost(id: 'post-1');
      expect(res.getPost.coAuthor, isNull);
    });

    test('Post scalar fields are deserialized correctly', () async {
      final res = await client.queries.getPost(id: 'post-1');
      expect(res.getPost.title, equals('Hello World'));
      expect(res.getPost.viewCount, equals(128));
    });
  });

  group('@glSkipOnClient field excluded from deserialization', () {
    test('AuditEntry has no internalNote field', () async {
      // Server returns internalNote — the generated class must simply ignore it.
      adapter.registerData('getAuditEntry', {
        'getAuditEntry': kAuditEntryWithExtraJson,
      });
      final res = await client.queries.getAuditEntry(id: 'audit-2');
      expect(res.getAuditEntry.id, equals('audit-2'));
      expect(res.getAuditEntry.action, equals('LOGOUT'));
      // Compile-time check: res.getAuditEntry.internalNote does not exist.
    });
  });
}
