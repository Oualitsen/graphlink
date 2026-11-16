import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/client/graph_link_client.dart';
import 'package:graphlink_client_integration_tests/generated/types/graph_link_error.dart';
import 'real_server_adapter.dart';

// The server fails the first cachedFlaky / cachedFlakyNullable call per id and counts every call.
void main() {
  late GraphLinkClient client;
  late String id;
  var next = 0;
  setUp(() {
    client = newClient();
    id = 'dart-${DateTime.now().microsecondsSinceEpoch}-${next++}';
  });

  Future<int> serverCalls() async =>
      (await client.queries.cachedFlakyCalls(id: id)).cachedFlakyCalls;

  test('a failed response is not cached, the success after it is', () async {
    await expectLater(client.queries.cachedFlaky(id: id),
        throwsA(isA<List<GraphLinkError>>()));
    expect(await serverCalls(), 1);

    expect((await client.queries.cachedFlaky(id: id)).cachedFlaky.id, 'user-1');
    expect(await serverCalls(), 2);

    expect((await client.queries.cachedFlaky(id: id)).cachedFlaky.id, 'user-1');
    expect(await serverCalls(), 2);
  });

  test('a partial failure (200, null field, errors) is not cached', () async {
    await expectLater(client.queries.cachedFlakyNullable(id: id),
        throwsA(isA<List<GraphLinkError>>()));
    expect(await serverCalls(), 1);

    expect((await client.queries.cachedFlakyNullable(id: id)).cachedFlakyNullable!.id,
        'user-1');
    expect(await serverCalls(), 2);

    expect((await client.queries.cachedFlakyNullable(id: id)).cachedFlakyNullable!.id,
        'user-1');
    expect(await serverCalls(), 2);
  });
}
