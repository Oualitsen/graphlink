import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'support.dart';
import 'package:test/test.dart';

void main() {
  late GraphLinkClient client;
  late InMemoryGraphLinkCacheStore store;

  setUp(() async {
    await resetServer();
    store = InMemoryGraphLinkCacheStore();
    client = newClient(store: store);
  });

  group('@glCache on REST queries', () {
    test('the second call is served from the cache, with no request', () async {
      final first = await client.queries.counter(name: 'a');
      final second = await client.queries.counter(name: 'a');
      expect([first.n, second.n], [1, 1]);
      expect((await client.queries.counterUncached(name: 'a')).n, 2);
    });

    test('different arguments are different entries', () async {
      expect((await client.queries.counter(name: 'a')).n, 1);
      expect((await client.queries.counter(name: 'b')).n, 1);
      expect((await client.queries.counter(name: 'a')).n, 1);
    });

    test('an operation without @glCache is never cached; @glNoCache neither', () async {
      expect((await client.queries.counterUncached(name: 'u')).n, 1);
      expect((await client.queries.counterUncached(name: 'u')).n, 2);
      expect((await client.queries.counterNoCache(name: 'u')).n, 3);
      expect((await client.queries.counterNoCache(name: 'u')).n, 4);
    });

    test('an entry expires after its ttl', () async {
      expect((await client.queries.counterShort(name: 's')).n, 1);
      expect((await client.queries.counterShort(name: 's')).n, 1);
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect((await client.queries.counterShort(name: 's')).n, 2);
    });

    test('the cache is shared by every client using the same store', () async {
      await client.queries.counter(name: 'shared');
      final other = newClient(store: store);
      expect((await other.queries.counter(name: 'shared')).n, 1);
    });

    test('separate stores do not share entries', () async {
      await client.queries.counter(name: 'iso');
      expect((await newClient().queries.counter(name: 'iso')).n, 2);
    });
  });

  group('@glCacheInvalidate on REST mutations', () {
    test('invalidates the entries holding the tag, after a 2xx response', () async {
      expect((await client.queries.counter(name: 'c')).n, 1);
      await client.mutations.bump(name: 'c');
      expect((await client.queries.counter(name: 'c')).n, 102);
    });

    test('leaves entries with other tags alone', () async {
      expect((await client.queries.counterOther(name: 'o')).n, 1);
      expect((await client.queries.counter(name: 'o')).n, 2);
      await client.mutations.bump(name: 'o');
      expect((await client.queries.counterOther(name: 'o')).n, 1);
      expect((await client.queries.counter(name: 'o')).n, greaterThan(100));
    });

    test('all: true clears everything', () async {
      await client.queries.counter(name: 'x');
      await client.queries.counterOther(name: 'x');
      await client.mutations.resetAll(name: 'x');
      expect((await client.queries.counter(name: 'x')).n, 1);
      expect((await client.queries.counterOther(name: 'x')).n, 2);
    });

    test('a failed mutation does not invalidate', () async {
      await client.queries.counter(name: 'f');
      await expectLater(client.mutations.bumpFails(code: 500), throwsA(isA<RestError>()));
      expect((await client.queries.counter(name: 'f')).n, 1);
    });

    test('a 204 mutation still invalidates', () async {
      await client.queries.counter(name: 'g');
      await client.mutations.bumpFails(code: 204);
      expect((await client.queries.counter(name: 'g')).n, 2);
    });
  });

  group('failures', () {
    test('an error response is not cached', () async {
      final writes = _CountingStore();
      final c = newClient(store: writes);
      await expectLater(c.queries.cachedStatus(code: 500), throwsA(isA<RestError>()));
      expect(writes.sets, 0);
      expect((await c.queries.cachedStatus(code: 200))!.id, 'p1');
      expect(writes.sets, 1);
    });

    test('a response that fails to decode is not cached', () async {
      final writes = _CountingStore();
      final c = newClient(store: writes);
      await expectLater(c.queries.cachedBad(), throwsA(anything));
      await expectLater(c.queries.cachedBad(), throwsA(anything));
      expect(writes.sets, 0);
    });

    test('staleIfOffline serves the expired entry on a transport failure only', () async {
      await client.queries.counterOffline(name: 'off');
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      final offline = newClient(baseUrl: 'http://127.0.0.1:1', store: store);
      expect((await offline.queries.counterOffline(name: 'off')).n, 1);
    });

    test('without staleIfOffline a transport failure surfaces', () async {
      await client.queries.counterShort(name: 'off2');
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      final offline = newClient(baseUrl: 'http://127.0.0.1:1', store: store);
      await expectLater(offline.queries.counterShort(name: 'off2'), throwsA(isNot(isA<RestError>())));
    });

    test('a fresh entry is served even when the server is unreachable', () async {
      await client.queries.counter(name: 'fresh');
      final offline = newClient(baseUrl: 'http://127.0.0.1:1', store: store);
      expect((await offline.queries.counter(name: 'fresh')).n, 1);
    });

    test('nothing cached and the server unreachable is a transport error', () async {
      final offline = newClient(baseUrl: 'http://127.0.0.1:1', store: store);
      await expectLater(offline.queries.counter(name: 'never'), throwsA(isNot(isA<RestError>())));
    });
  });
}

class _CountingStore extends InMemoryGraphLinkCacheStore {
  int sets = 0;

  @override
  Future<void> set(String key, String value) {
    sets++;
    return super.set(key, value);
  }
}
