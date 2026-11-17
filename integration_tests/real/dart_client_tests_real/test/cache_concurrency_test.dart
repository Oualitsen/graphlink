import 'package:test/test.dart';
import 'real_server_adapter.dart';

int _n = 0;

void main() {
  late String id;
  setUp(() => id = 'dart-${DateTime.now().microsecondsSinceEpoch}-${_n++}');

  test('concurrent requests for two different keys make two calls', () async {
    final client = newClient();
    await Future.wait([
      client.queries.cachedSlow(id: '$id-a', delayMs: 300),
      client.queries.cachedSlow(id: '$id-b', delayMs: 300),
    ]);
    expect((await client.queries.cachedSlowCalls(id: '$id-a')).cachedSlowCalls, 1);
    expect((await client.queries.cachedSlowCalls(id: '$id-b')).cachedSlowCalls, 1);
  });

  test('concurrent requests for the same key share one call', () async {
    final client = newClient();
    final results = await Future.wait([
      client.queries.cachedSlow(id: id, delayMs: 300),
      client.queries.cachedSlow(id: id, delayMs: 300),
      client.queries.cachedSlow(id: id, delayMs: 300),
    ]);
    expect(results.map((r) => r.cachedSlow), [0, 0, 0]);
    expect((await client.queries.cachedSlowCalls(id: id)).cachedSlowCalls, 1);
  });

  test('a response that was in flight during an invalidation is not stored', () async {
    final client = newClient();
    final slow = client.queries.cachedSlow(id: id, delayMs: 600);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await client.mutations.bumpSlow(id: id);
    expect((await slow).cachedSlow, 0);
    expect((await client.queries.cachedSlow(id: id, delayMs: 600)).cachedSlow, 1);
  });
}
