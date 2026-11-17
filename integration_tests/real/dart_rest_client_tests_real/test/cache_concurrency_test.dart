import 'dart:async';

import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'package:test/test.dart';
import 'support.dart';

int _n = 0;

class _PausingStore implements GraphLinkCacheStore {
  final _inner = InMemoryGraphLinkCacheStore();
  final reached = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> set(String key, String value) async {
    if (!key.startsWith('__tag__') && !reached.isCompleted) {
      reached.complete();
      await release.future;
    }
    await _inner.set(key, value);
  }

  @override
  Future<String?> get(String key) => _inner.get(key);

  @override
  Future<void> invalidate(String key) => _inner.invalidate(key);

  @override
  Future<void> invalidateAll() => _inner.invalidateAll();
}

void main() {
  late String name;
  late GraphLinkClient client;

  setUp(() async {
    await resetServer();
    name = 'dart-${DateTime.now().microsecondsSinceEpoch}-${_n++}';
    client = newClient(store: InMemoryGraphLinkCacheStore());
  });

  test('concurrent requests for two different keys make two calls', () async {
    await Future.wait([
      client.queries.counterSlow(name: '$name-a', delayMs: 300),
      client.queries.counterSlow(name: '$name-b', delayMs: 300),
    ]);
    expect((await client.queries.counterCalls(name: '$name-a')).n, 1);
    expect((await client.queries.counterCalls(name: '$name-b')).n, 1);
  });

  test('concurrent requests for the same key share one call', () async {
    final results = await Future.wait([
      client.queries.counterSlow(name: name, delayMs: 300),
      client.queries.counterSlow(name: name, delayMs: 300),
      client.queries.counterSlow(name: name, delayMs: 300),
    ]);
    expect(results.map((r) => r.n), [1, 1, 1]);
    expect((await client.queries.counterCalls(name: name)).n, 1);
  });

  test('a response that was in flight during an invalidation is not stored', () async {
    final slow = client.queries.counterSlow(name: name, delayMs: 600);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await client.mutations.touchSlow(name: name);
    expect((await slow).n, 1);
    expect((await client.queries.counterSlow(name: name, delayMs: 600)).n, 2);
  });

  test('an invalidation that arrives while the response is being stored removes it', () async {
    final store = _PausingStore();
    final paused = newClient(store: store);
    final first = paused.queries.counterSlow(name: name, delayMs: 50);
    await store.reached.future;
    final touch = paused.mutations.touchSlow(name: name);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    store.release.complete();
    await Future.wait([first, touch]);
    expect((await paused.queries.counterSlow(name: name, delayMs: 50)).n, 2);
  });
}
