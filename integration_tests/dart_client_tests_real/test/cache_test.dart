import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/enums/user_status.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/create_user_input.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/address_input.dart';
import 'real_server_adapter.dart';

const _minimalInput = CreateUserInput(
  name: 'Alice Smith',
  email: 'alice@test.com',
  status: UserStatus.active,
  address:
      AddressInput(street: '123 Main St', city: 'Springfield', country: 'US'),
);

void main() {
  // Each test gets a fresh client — fresh in-memory cache store.
  late GraphLinkClient client;
  setUp(() => client = newClient());

  // ── Cache hit ──────────────────────────────────────────────────────────────

  group('cache hit', () {
    test('second getCachedUser call returns same data as first', () async {
      final first = await client.queries.getCachedUser(id: 'user-1');
      final second =
          await client.queries.getCachedUser(id: 'user-1');
      expect(second.getCachedUser.id, equals(first.getCachedUser.id));
      expect(second.getCachedUser.name, equals('Alice Smith'));
    });
  });

  // ── Data integrity after invalidation ─────────────────────────────────────

  group('tag invalidation — data still accessible after createCachedUser', () {
    test('getCachedUser works after createCachedUser invalidation', () async {
      await client.queries.getCachedUser(id: 'user-1');
      await client.mutations.createCachedUser(input: _minimalInput);
      final res = await client.queries.getCachedUser(id: 'user-1');
      expect(res.getCachedUser.name, equals('Alice Smith'));
    });

    test('listCachedUsers works after createCachedUser invalidation', () async {
      await client.queries.listCachedUsers();
      await client.mutations.createCachedUser(input: _minimalInput);
      final res = await client.queries.listCachedUsers();
      expect(res.listCachedUsers, isNotEmpty);
    });
  });

  group('multi-tag invalidation — data accessible after transferPost', () {
    test('getCachedUser works after transferPost', () async {
      await client.queries.getCachedUser(id: 'user-1');
      await client.mutations
          .transferPost(postId: 'post-1', newAuthorId: 'user-2');
      final res = await client.queries.getCachedUser(id: 'user-1');
      expect(res.getCachedUser.id, equals('user-1'));
    });

    test('getCachedPost works after transferPost', () async {
      await client.queries.getCachedPost(id: 'post-1');
      await client.mutations
          .transferPost(postId: 'post-1', newAuthorId: 'user-2');
      final res = await client.queries.getCachedPost(id: 'post-1');
      expect(res.getCachedPost.id, equals('post-1'));
    });
  });

  // ── resetAll ───────────────────────────────────────────────────────────────

  group('resetAll', () {
    test('returns true', () async {
      final res = await client.mutations.resetAll();
      expect(res.resetAll, isTrue);
    });

    test('cached queries still work after resetAll', () async {
      await client.queries.getCachedUser(id: 'user-1');
      await client.mutations.resetAll();
      final res = await client.queries.getCachedUser(id: 'user-1');
      expect(res.getCachedUser.name, equals('Alice Smith'));
    });
  });

  // ── TTL expiry ─────────────────────────────────────────────────────────────

  group('TTL expiry', () {
    test('getStaleUser re-fetches after TTL expires (ttl=1s)', () async {
      await client.queries.getStaleUser(id: 'user-1');
      await Future.delayed(const Duration(seconds: 2));
      // After TTL expires the client fetches fresh — must not throw.
      final res = await client.queries.getStaleUser(id: 'user-1');
      expect(res.getStaleUser, isNotNull);
      expect(res.getStaleUser!.name, equals('Alice Smith'));
    });
  });

  // ── No cache — plain queries ───────────────────────────────────────────────

  group('no cache', () {
    test('getUser (no @glCache) returns correct data on repeated calls',
        () async {
      final first = await client.queries.getUser(id: 'user-1');
      final second = await client.queries.getUser(id: 'user-1');
      expect(first.getUser.id, equals(second.getUser.id));
    });
  });
}
