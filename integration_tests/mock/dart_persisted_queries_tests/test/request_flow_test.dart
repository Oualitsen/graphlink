import 'dart:convert';

import 'package:test/test.dart';
import 'package:graphlink_persisted_queries_tests/generated/graphlink.dart';
import '../../dart_client_tests/test/fixtures.dart';
import 'apq_server.dart';

void main() {
  late ApqServer server;
  late GraphLinkClient client;

  setUp(() {
    server = ApqServer();
    client = GraphLinkClient(adapter: server.call, getAdapter: server.get, wsAdapter: NoWebSocketAdapter());
  });

  Map<String, dynamic> hashOf(Map<String, dynamic> request) =>
      ((request['extensions'] as Map)['persistedQuery'] as Map).cast<String, dynamic>();

  group('a long query', () {
    setUp(() => server.respondTo('persistedLongQuery', {'getUser': kUserAliceJson}));

    test('is sent as a hash first and registered by the retry', () async {
      final res = await client.queries.persistedLongQuery(id: 'user-1');

      expect(res.getUser.name, 'Alice Smith');
      expect(server.requests, hasLength(2));
      final hashOnly = server.requests[0];
      expect(hashOnly.containsKey('query'), isFalse);
      expect(hashOnly['operationName'], 'persistedLongQuery');
      expect(hashOnly['variables'], {'id': 'user-1'});
      final retry = server.requests[1];
      expect(retry['query'], isA<String>());
      expect(retry['variables'], {'id': 'user-1'});
    });

    test('the hash is the SHA-256 of the query that the retry carries', () async {
      await client.queries.persistedLongQuery(id: 'user-1');

      final retry = server.requests[1];
      expect(hashOf(retry), {'version': 1, 'sha256Hash': GraphLinkSha256.hex(retry['query'] as String)});
      expect(hashOf(server.requests[0]), hashOf(retry));
    });

    test('is a single request once the server knows it', () async {
      await client.queries.persistedLongQuery(id: 'user-1');
      server.requests.clear();

      await client.queries.persistedLongQuery(id: 'user-2');

      expect(server.requests, hasLength(1));
      expect(server.isHashOnly(server.requests.single), isTrue);
      expect(server.requests.single['variables'], {'id': 'user-2'});
    });

    test('is registered again after the server evicts it', () async {
      await client.queries.persistedLongQuery(id: 'user-1');
      server.evict();
      server.requests.clear();

      final res = await client.queries.persistedLongQuery(id: 'user-1');

      expect(res.getUser.name, 'Alice Smith');
      expect(server.requests, hasLength(2));
      expect(server.isHashOnly(server.requests[0]), isTrue);
      expect(server.requests[1].containsKey('query'), isTrue);
    });
  });

  group('a server that reports a missing hash only by its code', () {
    test('still gets the retry with the query', () async {
      server.notFoundMessage = 'Unknown query';
      server.respondTo('persistedLongQuery', {'getUser': kUserAliceJson});

      final res = await client.queries.persistedLongQuery(id: 'user-1');

      expect(res.getUser.name, 'Alice Smith');
      expect(server.requests, hasLength(2));
      expect(server.requests[1].containsKey('query'), isTrue);
    });
  });

  group('a short query', () {
    test('is sent in full, with no hash', () async {
      server.respondTo('persistedShortQuery', {'listUsers': []});

      await client.queries.persistedShortQuery();

      expect(server.requests, hasLength(1));
      expect(server.requests.single['query'], contains('listUsers'));
      expect(server.requests.single.containsKey('extensions'), isFalse);
    });
  });

  group('a long mutation', () {
    test('uses the same hash-then-register flow', () async {
      server.respondTo('persistedLongMutation', {'createUser': kUserAliceJson});

      final res = await client.mutations.persistedLongMutation(
        input: CreateUserInput(
          name: 'Alice',
          email: 'a@test.com',
          status: UserStatus.active,
          address: const AddressInput(street: 's', city: 'c', country: 'x'),
        ),
      );

      expect(res.createUser.name, 'Alice Smith');
      expect(server.requests, hasLength(2));
      expect(server.isHashOnly(server.requests[0]), isTrue);
      expect(server.requests[1].containsKey('query'), isTrue);
    });
  });

  group('a server without APQ', () {
    setUp(() {
      server.supported = false;
      server.respondTo('persistedLongQuery', {'getUser': kUserAliceJson});
    });

    test('gets the full query right after the first refusal', () async {
      final res = await client.queries.persistedLongQuery(id: 'user-1');

      expect(res.getUser.name, 'Alice Smith');
      expect(server.requests, hasLength(2));
      expect(server.requests[1].containsKey('query'), isTrue);
      expect(server.requests[1].containsKey('extensions'), isFalse);
    });

    test('is not asked about hashes again', () async {
      await client.queries.persistedLongQuery(id: 'user-1');
      server.requests.clear();

      await client.queries.persistedLongQuery(id: 'user-2');

      expect(server.requests, hasLength(1));
      expect(server.requests.single.containsKey('query'), isTrue);
      expect(server.requests.single.containsKey('extensions'), isFalse);
    });
  });

  group('errors that are not a missing persisted query', () {
    test('a GraphQL error is returned as is, without a second request', () async {
      server.respondTo('persistedLongQuery', {'getUser': kUserAliceJson});
      await client.queries.persistedLongQuery(id: 'user-1');
      server.requests.clear();
      server.respondWithErrors('persistedLongQuery', [
        {'message': 'boom'},
      ]);

      await expectLater(client.queries.persistedLongQuery(id: 'user-1'), throwsA(anything));
      expect(server.requests, hasLength(1));
    });

    test('a transport failure propagates, without a second request', () async {
      server.respondTo('persistedLongMutation', {'createUser': kUserAliceJson});
      server.failWith = Exception('timeout');

      await expectLater(
        client.mutations.persistedLongMutation(
          input: CreateUserInput(
            name: 'Alice',
            email: 'a@test.com',
            status: UserStatus.active,
            address: const AddressInput(street: 's', city: 'c', country: 'x'),
          ),
        ),
        throwsA(isA<Exception>()),
      );
      expect(server.methods, ['POST']);
    });
  });

  group('a cached query', () {
    test('hashes the assembled request, not its pieces', () async {
      server.respondTo('fetchCachedPair', {'user': kUserAliceJson, 'post': kPostJson});

      final res = await client.queries.fetchCachedPair(userId: 'user-1', postId: 'post-1');

      expect(res.user.name, 'Alice Smith');
      expect(server.requests, hasLength(2));
      final retry = server.requests[1];
      expect(hashOf(retry)['sha256Hash'], GraphLinkSha256.hex(retry['query'] as String));
      expect(jsonDecode(jsonEncode(retry))['query'], contains('getCachedUser'));
    });
  });
}
