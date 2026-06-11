import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/types/user_result.dart';
import 'package:graphlink_client_integration_tests/generated/types/post_result.dart';
import 'package:graphlink_client_integration_tests/generated/enums/user_status.dart';
import 'real_server_adapter.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  // ── fetchUserAndPost ───────────────────────────────────────────────────────

  group('fetchUserAndPost', () {
    test('res.user.name is Alice Smith', () async {
      final res = await client.queries
          .fetchUserAndPost(userId: 'user-1', postId: 'post-1', limit: 10);
      expect(res.user.name, equals('Alice Smith'));
    });

    test('res.user.id is user-1', () async {
      final res = await client.queries
          .fetchUserAndPost(userId: 'user-1', postId: 'post-1', limit: 10);
      expect(res.user.id, equals('user-1'));
    });

    test('res.post.title is Hello World', () async {
      final res = await client.queries
          .fetchUserAndPost(userId: 'user-1', postId: 'post-1', limit: 10);
      expect(res.post.title, equals('Hello World'));
    });

    test('res.post.author.id is user-1', () async {
      final res = await client.queries
          .fetchUserAndPost(userId: 'user-1', postId: 'post-1', limit: 10);
      expect(res.post.author.id, equals('user-1'));
    });
  });

  // ── fetchUserSummary — projected type ─────────────────────────────────────

  group('fetchUserSummary — projected type', () {
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
      expect(res.getUser.status, equals(UserStatus.ACTIVE));
    });
  });

  // ── fetchCachedPair ────────────────────────────────────────────────────────

  group('fetchCachedPair — data correctness', () {
    test('user and post data is correct', () async {
      final res = await client.queries
          .fetchCachedPair(userId: 'user-1', postId: 'post-1', limit: 10);
      expect(res.user.name, equals('Alice Smith'));
      expect(res.post.title, equals('Hello World'));
    });

    test('second call with same args returns correct data', () async {
      await client.queries
          .fetchCachedPair(userId: 'user-1', postId: 'post-1', limit: 10);
      final res = await client.queries
          .fetchCachedPair(userId: 'user-1', postId: 'post-1', limit: 10);
      expect(res.user.name, equals('Alice Smith'));
      expect(res.post.title, equals('Hello World'));
    });
  });

  // ── runSearch — custom query, union dispatch ──────────────────────────────
  // Note: the auto-generated search query uses a fragment structure that Spring
  // rejects; use runSearch (custom operation) for union dispatch testing.

  group('runSearch — __typename dispatch', () {
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
      expect(userResult.name, equals('Alice Smith'));
    });

    test('PostResult has correct title', () async {
      final res = await client.queries.runSearch(term: 'test');
      final postResult = res.search.last as PostResult;
      expect(postResult.title, equals('Hello World'));
    });
  });
}
