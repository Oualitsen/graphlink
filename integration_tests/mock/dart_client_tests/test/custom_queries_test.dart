import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/types/user_result.dart';
import 'package:graphlink_client_integration_tests/generated/types/post_result.dart';
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

  // ── fetchUserAndPost ───────────────────────────────────────────────────────

  group('fetchUserAndPost', () {
    setUp(() {
      adapter.registerData('fetchUserAndPost', {
        'user': kUserAliceJson,
        'post': kPostJson,
      });
    });

    test('res.user.name is correct', () async {
      final res = await client.queries.fetchUserAndPost(userId: 'user-1', postId: 'post-1');
      expect(res.user.name, equals('Alice Smith'));
    });

    test('res.user.id is correct', () async {
      final res = await client.queries.fetchUserAndPost(userId: 'user-1', postId: 'post-1');
      expect(res.user.id, equals('user-1'));
    });

    test('res.post.title is correct', () async {
      final res = await client.queries.fetchUserAndPost(userId: 'user-1', postId: 'post-1');
      expect(res.post.title, equals('Hello World'));
    });

    test('res.post.author.id is correct', () async {
      final res = await client.queries.fetchUserAndPost(userId: 'user-1', postId: 'post-1');
      expect(res.post.author?.id, equals('user-1'));
    });
  });

  // ── fetchUserSummary — projected type ─────────────────────────────────────

  group('fetchUserSummary — projected type', () {
    setUp(() {
      adapter.registerData('fetchUserSummary', {
        'getUser': {'id': 'user-1', 'name': 'Alice Smith', 'status': 'ACTIVE'},
      });
    });

    test('id is accessible', () async {
      final res = await client.queries.fetchUserSummary(id: 'user-1');
      expect(res.getUser.id, equals('user-1'));
    });

    test('name is accessible', () async {
      final res = await client.queries.fetchUserSummary(id: 'user-1');
      expect(res.getUser.name, equals('Alice Smith'));
    });

    test('status is deserialized as enum', () async {
      final res = await client.queries.fetchUserSummary(id: 'user-1');
      expect(res.getUser.status, equals(UserStatus.active));
    });
  });

  // ── fetchCachedPair — independent caching ────────────────────────────────

  group('fetchCachedPair — independent caching', () {
    test('second call with same args hits cache — adapter called once', () async {
      adapter.registerData('fetchCachedPair', {
        'user': kUserAliceJson,
        'post': kPostJson,
      });

      await client.queries.fetchCachedPair(userId: 'user-1', postId: 'post-1');
      await client.queries.fetchCachedPair(userId: 'user-1', postId: 'post-1');

      expect(adapter.callCount, equals(1));
    });

    test('different postId causes a second network call', () async {
      adapter.registerData('fetchCachedPair', {
        'user': kUserAliceJson,
        'post': kPostJson,
      });

      await client.queries.fetchCachedPair(userId: 'user-1', postId: 'post-1');
      await client.queries.fetchCachedPair(userId: 'user-1', postId: 'post-2');

      expect(adapter.callCount, equals(2));
    });

    test('data is correct on cache hit', () async {
      adapter.registerData('fetchCachedPair', {
        'user': kUserAliceJson,
        'post': kPostJson,
      });

      await client.queries.fetchCachedPair(userId: 'user-1', postId: 'post-1');
      final res = await client.queries.fetchCachedPair(userId: 'user-1', postId: 'post-1');

      expect(res.user.name, equals('Alice Smith'));
      expect(res.post.title, equals('Hello World'));
    });
  });

  // ── search — auto-generated query, union dispatch ────────────────────────

  group('search — auto-generated __typename dispatch', () {
    setUp(() {
      adapter.registerData('search', {
        'search': [
          {'__typename': 'UserResult', 'id': 'ur-1', 'name': 'Alice', 'email': 'alice@test.com'},
          {'__typename': 'PostResult', 'id': 'pr-1', 'title': 'Hello World'},
        ],
      });
    });

    test('search list has two elements', () async {
      final res = await client.queries.search(term: 'test');
      expect(res.search, hasLength(2));
    });

    test('first element is dispatched as UserResult', () async {
      final res = await client.queries.search(term: 'test');
      expect(res.search.first, isA<UserResult>());
    });

    test('second element is dispatched as PostResult', () async {
      final res = await client.queries.search(term: 'test');
      expect(res.search.last, isA<PostResult>());
    });

    test('UserResult fields are correct', () async {
      final res = await client.queries.search(term: 'test');
      final u = res.search.first as UserResult;
      expect(u.id, equals('ur-1'));
      expect(u.name, equals('Alice'));
      expect(u.email, equals('alice@test.com'));
    });

    test('PostResult fields are correct', () async {
      final res = await client.queries.search(term: 'test');
      final p = res.search.last as PostResult;
      expect(p.id, equals('pr-1'));
      expect(p.title, equals('Hello World'));
    });

    test('unknown __typename throws ArgumentError', () async {
      adapter.registerData('search', {
        'search': [
          {'__typename': 'UnknownType', 'id': 'x-1'},
        ],
      });
      expect(
        client.queries.search(term: 'test'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ── runSearch — custom query, union dispatch ───────────────────────────────

  group('runSearch — __typename dispatch', () {
    setUp(() {
      adapter.registerData('runSearch', {
        'search': [
          {'__typename': 'UserResult', 'id': 'ur-1', 'name': 'Alice', 'email': 'alice@test.com'},
          {'__typename': 'PostResult', 'id': 'pr-1', 'title': 'Hello World'},
        ],
      });
    });

    test('search list has two elements', () async {
      final res = await client.queries.runSearch(term: 'test');
      expect(res.search, hasLength(2));
    });

    test('first element is dispatched as UserResult', () async {
      final res = await client.queries.runSearch(term: 'test');
      expect(res.search.first, isA<UserResult>());
    });

    test('second element is dispatched as PostResult', () async {
      final res = await client.queries.runSearch(term: 'test');
      expect(res.search.last, isA<PostResult>());
    });

    test('UserResult has correct name', () async {
      final res = await client.queries.runSearch(term: 'test');
      final userResult = res.search.first as UserResult;
      expect(userResult.name, equals('Alice'));
    });

    test('UserResult has correct email', () async {
      final res = await client.queries.runSearch(term: 'test');
      final userResult = res.search.first as UserResult;
      expect(userResult.email, equals('alice@test.com'));
    });

    test('PostResult has correct title', () async {
      final res = await client.queries.runSearch(term: 'test');
      final postResult = res.search.last as PostResult;
      expect(postResult.title, equals('Hello World'));
    });
  });
}
