import 'package:test/test.dart';
import 'package:graphlink_persisted_queries_tests/generated/graphlink.dart';
import '../../../../mock/dart_client_tests/test/fixtures.dart';
import 'apq_server.dart';

void main() {
  late ApqServer server;
  late GraphLinkClient client;

  setUp(() {
    server = ApqServer();
    client = GraphLinkClient(adapter: server.call, getAdapter: server.get, wsAdapter: NoWebSocketAdapter());
    server.respondTo('persistedLongQuery', {'getUser': kUserAliceJson});
    server.respondTo('persistedShortQuery', {'listUsers': []});
    server.respondTo('persistedLongMutation', {'createUser': kUserAliceJson});
  });

  Future<void> createUser() => client.mutations.persistedLongMutation(
        input: CreateUserInput(
          name: 'Alice',
          email: 'a@test.com',
          status: UserStatus.active,
          address: const AddressInput(street: 's', city: 'c', country: 'x'),
        ),
      );

  group('a long query', () {
    test('asks with a GET first and registers with a POST', () async {
      await client.queries.persistedLongQuery(id: 'user-1');

      expect(server.methods, ['GET', 'POST']);
      expect(server.isHashOnly(server.requests[0]), isTrue);
      expect(server.requests[1].containsKey('query'), isTrue);
    });

    test('is a single GET once the server knows it', () async {
      await client.queries.persistedLongQuery(id: 'user-1');
      server.methods.clear();

      await client.queries.persistedLongQuery(id: 'user-2');

      expect(server.methods, ['GET']);
    });

    test('hands the GET adapter the hash-only payload, with no query', () async {
      await client.queries.persistedLongQuery(id: 'user-1');

      final get = server.requests.first;
      expect(get.keys.toSet(), {'operationName', 'variables', 'extensions'});
    });
  });

  group('requests that never use GET', () {
    test('a short query is a plain POST', () async {
      await client.queries.persistedShortQuery();

      expect(server.methods, ['POST']);
    });

    test('a mutation sends its hash over POST', () async {
      await createUser();

      expect(server.methods, ['POST', 'POST']);
      expect(server.isHashOnly(server.requests[0]), isTrue);
    });
  });

  group('a server that refuses GET', () {
    setUp(() => server.getSupported = false);

    test('gets the same hash-only request as a POST', () async {
      final res = await client.queries.persistedLongQuery(id: 'user-1');

      expect(res.getUser.name, 'Alice Smith');
      expect(server.methods, ['GET', 'POST', 'POST']);
      expect(server.requests, hasLength(2));
      expect(server.isHashOnly(server.requests[0]), isTrue);
      expect(server.requests[1].containsKey('query'), isTrue);
    });

    test('is not asked with a GET again', () async {
      await client.queries.persistedLongQuery(id: 'user-1');
      server.methods.clear();

      await client.queries.persistedLongQuery(id: 'user-2');

      expect(server.methods, ['POST']);
    });
  });

  group('a server without APQ', () {
    test('answers the GET with a refusal, then gets the full query by POST', () async {
      server.supported = false;

      await client.queries.persistedLongQuery(id: 'user-1');

      expect(server.methods, ['GET', 'POST']);
      expect(server.requests[1].containsKey('query'), isTrue);
      expect(server.requests[1].containsKey('extensions'), isFalse);
    });
  });

  group('other GET failures', () {
    test('propagate untouched, with no POST', () async {
      server.getFailWith = Exception('network down');

      await expectLater(client.queries.persistedLongQuery(id: 'user-1'), throwsA(isA<Exception>()));
      expect(server.methods, ['GET']);
    });
  });
}
