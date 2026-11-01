import 'package:test/test.dart';
import 'package:graphlink_persisted_queries_tests/generated/client/graph_link_client.dart';
import 'apq_server.dart';

void main() {
  late GraphLinkClient client;

  setUp(() {
    client = GraphLinkClient(adapter: ApqServer().call, getAdapter: ApqServer().get, wsAdapter: NoWebSocketAdapter());
  });

  group('glHash', () {
    test('hashes a query like a reference SHA-256', () {
      expect(client.queries.glHash('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect(client.queries.glHash(''), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('hashes a real GraphQL document', () {
      expect(
        client.queries.glHash(r'query GetUser($id: ID!){getUser(id:$id){id name}}'),
        '76c03fc2e5cc623d71d65ac35823728a3fd45da3b453349dafa9b6fc1d1b7abc',
      );
    });

    test('is the same for repeated calls', () {
      final first = client.queries.glHash('query A{a}');
      expect(client.queries.glHash('query A{a}'), first);
      expect(client.queries.glHash('query B{b}'), isNot(first));
    });

    test('is shared by queries and mutations through the base class', () {
      expect(client.mutations.glHash('abc'), client.queries.glHash('abc'));
    });
  });
}
