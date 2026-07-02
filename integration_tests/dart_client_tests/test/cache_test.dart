import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/enums/user_status.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/create_user_input.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/address_input.dart';
import 'fixtures.dart';
import 'mock_adapter.dart';

const _minimalInput = CreateUserInput(
  name: 'Alice Smith',
  email: 'alice@test.com',
  status: UserStatus.active,
  address: AddressInput(street: '123 Main St', city: 'Springfield', country: 'US'),
);

void main() {
  late MockAdapter adapter;
  late GraphLinkClient client;

  // Fresh client per test — each test starts with an empty in-memory store.
  setUp(() {
    adapter = MockAdapter();
    client = GraphLinkClient(adapter: adapter.call, wsAdapter: MockWebSocketAdapter());
  });

  // ── 1. Cache hit ──────────────────────────────────────────────────────────

  group('cache hit', () {
    test('getCachedUser called twice with same id — adapter called once', () async {
      adapter.registerData('getCachedUser', {'getCachedUser': kUserAliceJson});

      await client.queries.getCachedUser(id: 'user-1');
      await client.queries.getCachedUser(id: 'user-1');

      expect(adapter.callCount, equals(1));
    });

    test('second call returns same data as first', () async {
      adapter.registerData('getCachedUser', {'getCachedUser': kUserAliceJson});

      final first = await client.queries.getCachedUser(id: 'user-1');
      final second = await client.queries.getCachedUser(id: 'user-1');

      expect(second.getCachedUser.id, equals(first.getCachedUser.id));
      expect(second.getCachedUser.name, equals('Alice Smith'));
    });
  });

  // ── 2. Different args — each key is cached independently ──────────────────

  group('cache miss on different args', () {
    test('getCachedUser with two different ids — adapter called twice', () async {
      adapter.registerData('getCachedUser', {'getCachedUser': kUserAliceJson});

      await client.queries.getCachedUser(id: 'user-1');
      await client.queries.getCachedUser(id: 'user-2');

      expect(adapter.callCount, equals(2));
    });

    test('third call with first id is still a hit — adapter not called again', () async {
      adapter.registerData('getCachedUser', {'getCachedUser': kUserAliceJson});

      await client.queries.getCachedUser(id: 'user-1');
      await client.queries.getCachedUser(id: 'user-2');
      await client.queries.getCachedUser(id: 'user-1');

      expect(adapter.callCount, equals(2));
    });
  });

  // ── 3. Tag invalidation ───────────────────────────────────────────────────

  group('tag invalidation — createCachedUser invalidates "users"', () {
    test('getCachedUser misses after createCachedUser', () async {
      adapter.registerData('getCachedUser', {'getCachedUser': kUserAliceJson});
      adapter.registerData('createCachedUser', {'createCachedUser': kUserAliceJson});

      await client.queries.getCachedUser(id: 'user-1'); // count: 1
      await client.queries.getCachedUser(id: 'user-1'); // count: 1 — hit
      expect(adapter.callCount, equals(1));

      await client.mutations.createCachedUser(input: _minimalInput); // count: 2

      await client.queries.getCachedUser(id: 'user-1'); // count: 3 — miss
      expect(adapter.callCount, equals(3));
    });

    test('listCachedUsers also invalidated by createCachedUser (same tag)', () async {
      adapter.registerData('listCachedUsers', {'listCachedUsers': [kUserAliceJson]});
      adapter.registerData('createCachedUser', {'createCachedUser': kUserAliceJson});

      await client.queries.listCachedUsers(); // count: 1
      await client.queries.listCachedUsers(); // count: 1 — hit

      await client.mutations.createCachedUser(input: _minimalInput); // count: 2

      await client.queries.listCachedUsers(); // count: 3 — miss
      expect(adapter.callCount, equals(3));
    });
  });

  // ── 4. Multi-tag invalidation ─────────────────────────────────────────────

  group('multi-tag invalidation — transferPost invalidates "users" and "posts"', () {
    test('getCachedUser and getCachedPost both miss after transferPost', () async {
      adapter.registerData('getCachedUser', {'getCachedUser': kUserAliceJson});
      adapter.registerData('getCachedPost', {'getCachedPost': kPostJson});
      adapter.registerData('transferPost', {'transferPost': kPostJson});

      await client.queries.getCachedUser(id: 'user-1'); // count: 1
      await client.queries.getCachedPost(id: 'post-1'); // count: 2

      // Verify both are cached
      await client.queries.getCachedUser(id: 'user-1'); // count: 2 — hit
      await client.queries.getCachedPost(id: 'post-1'); // count: 2 — hit
      expect(adapter.callCount, equals(2));

      await client.mutations.transferPost(
        postId: 'post-1',
        newAuthorId: 'user-2',
      ); // count: 3

      await client.queries.getCachedUser(id: 'user-1'); // count: 4 — miss
      await client.queries.getCachedPost(id: 'post-1'); // count: 5 — miss
      expect(adapter.callCount, equals(5));
    });

    test('getCachedConfig (no shared tag) is NOT invalidated by transferPost', () async {
      adapter.registerData('getCachedConfig', {'getCachedConfig': kAllScalarsNullJson});
      adapter.registerData('transferPost', {'transferPost': kPostJson});

      await client.queries.getCachedConfig(); // count: 1
      await client.mutations.transferPost(
        postId: 'post-1',
        newAuthorId: 'user-2',
      ); // count: 2
      await client.queries.getCachedConfig(); // count: 2 — still cached

      expect(adapter.callCount, equals(2));
    });
  });

  // ── 5. Invalidate all ─────────────────────────────────────────────────────

  group('invalidate all — resetAll wipes the entire cache', () {
    test('all cached queries miss after resetAll', () async {
      adapter.registerData('getCachedUser', {'getCachedUser': kUserAliceJson});
      adapter.registerData('getCachedPost', {'getCachedPost': kPostJson});
      adapter.registerData('getCachedConfig', {'getCachedConfig': kAllScalarsNullJson});
      adapter.registerData('resetAll', {'resetAll': true});

      await client.queries.getCachedUser(id: 'user-1');  // count: 1
      await client.queries.getCachedPost(id: 'post-1');  // count: 2
      await client.queries.getCachedConfig();             // count: 3

      await client.mutations.resetAll(); // count: 4

      await client.queries.getCachedUser(id: 'user-1');  // count: 5 — miss
      await client.queries.getCachedPost(id: 'post-1');  // count: 6 — miss
      await client.queries.getCachedConfig();             // count: 7 — miss
      expect(adapter.callCount, equals(7));
    });

    test('resetAll returns true', () async {
      adapter.registerData('resetAll', {'resetAll': true});
      final res = await client.mutations.resetAll();
      expect(res.resetAll, isTrue);
    });
  });

  // ── 6. TTL expiry ─────────────────────────────────────────────────────────

  group('TTL expiry', () {
    test('getStaleUser re-fetches after ttl expires', () async {
      adapter.registerData('getStaleUser', {'getStaleUser': kUserAliceJson});

      await client.queries.getStaleUser(id: 'user-1'); // count: 1, ttl: 1s
      expect(adapter.callCount, equals(1));

      await Future.delayed(const Duration(seconds: 2));

      await client.queries.getStaleUser(id: 'user-1'); // count: 2 — expired
      expect(adapter.callCount, equals(2));
    });
  });

  // ── 7. staleIfOffline ─────────────────────────────────────────────────────

  group('staleIfOffline', () {
    test('returns stale value when network fails after TTL expires', () async {
      adapter.registerData('getStaleUser', {'getStaleUser': kUserAliceJson});

      await client.queries.getStaleUser(id: 'user-1'); // warms cache
      expect(adapter.callCount, equals(1));

      await Future.delayed(const Duration(seconds: 2)); // TTL expires

      adapter.simulateFailure = true;

      // Should return stale Alice, not throw
      final res = await client.queries.getStaleUser(id: 'user-1');
      expect(res.getStaleUser, isNotNull);
      expect(res.getStaleUser!.name, equals('Alice Smith'));

      // No new adapter call recorded (simulateFailure threw before recording)
      expect(adapter.callCount, equals(1));
    });

    test('throws when network fails and no stale value exists', () async {
      adapter.simulateFailure = true;

      expect(
        () => client.queries.getStaleUser(id: 'user-1'),
        throwsA(anything),
      );
    });
  });

  // ── 8. No cache — plain queries always hit the adapter ────────────────────

  group('no cache', () {
    test('getUser (no @glCache) — adapter called on every request', () async {
      adapter.registerData('getUser', {'getUser': kUserAliceJson});

      await client.queries.getUser(id: 'user-1');
      await client.queries.getUser(id: 'user-1');

      expect(adapter.callCount, equals(2));
    });
  });
}
