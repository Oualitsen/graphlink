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

  group('non-nullable query return', () {
    test('getUser returns a non-null User', () async {
      adapter.registerData('getUser', {'getUser': kUserAliceJson});
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser, isNotNull);
      expect(res.getUser.id, equals('user-1'));
    });
  });

  group('nullable query return', () {
    test('findUser returns null when server returns null', () async {
      adapter.registerData('findUser', {'findUser': null});
      final res = await client.queries.findUser(id: 'missing');
      expect(res.findUser, isNull);
    });

    test('findUser returns a User when server returns data', () async {
      adapter.registerData('findUser', {'findUser': kUserAliceJson});
      final res = await client.queries.findUser(id: 'user-1');
      expect(res.findUser, isNotNull);
      expect(res.findUser!.name, equals('Alice Smith'));
    });
  });

  group('nullable nested object fields', () {
    test('billingAddress is null when absent in response', () async {
      adapter.registerData('getUser', {'getUser': kUserAliceJson});
      final res = await client.queries.getUser(id: 'user-1');
      // kUserAliceJson has billingAddress: null
      expect(res.getUser.billingAddress, isNull);
    });

    test('billingAddress is non-null when present in response', () async {
      adapter.registerData('getUser', {'getUser': kUserBobJson});
      final res = await client.queries.getUser(id: 'user-2');
      expect(res.getUser.billingAddress, isNotNull);
      expect(res.getUser.billingAddress!.city, equals('Capital City'));
    });

    test('coAuthor on Post is null when absent', () async {
      adapter.registerData('getPost', {'getPost': kPostJson});
      final res = await client.queries.getPost(id: 'post-1');
      expect(res.getPost.coAuthor, isNull);
    });

    test('coAuthor on Post is non-null when present', () async {
      adapter.registerData('getPost', {'getPost': kPostWithCoAuthorJson});
      final res = await client.queries.getPost(id: 'post-2');
      expect(res.getPost.coAuthor, isNotNull);
      expect(res.getPost.coAuthor!.id, equals('user-2'));
    });
  });

  group('nullable scalar fields on nested type', () {
    test('Address.zip is null when absent', () async {
      adapter.registerData('getUser', {'getUser': kUserBobJson});
      final res = await client.queries.getUser(id: 'user-2');
      // kUserBobJson has address.zip: null
      expect(res.getUser.address.zip, isNull);
    });

    test('Address.zip has value when present', () async {
      adapter.registerData('getUser', {'getUser': kUserAliceJson});
      final res = await client.queries.getUser(id: 'user-1');
      // kUserAliceJson has address.zip: '12345'
      expect(res.getUser.address.zip, equals('12345'));
    });
  });

  group('nullable list fields', () {
    test('scores is null when server returns null', () async {
      adapter.registerData('getUser', {'getUser': kUserBobJson});
      final res = await client.queries.getUser(id: 'user-2');
      expect(res.getUser.scores, isNull);
    });

    test('scores is non-null list when server returns values', () async {
      adapter.registerData('getUser', {'getUser': kUserAliceJson});
      final res = await client.queries.getUser(id: 'user-1');
      expect(res.getUser.scores, isNotNull);
      expect(res.getUser.scores, containsAll([10, 20, 30]));
    });
  });
}
