import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'package:test/test.dart';
import 'support.dart';

int _n = 0;

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
}
