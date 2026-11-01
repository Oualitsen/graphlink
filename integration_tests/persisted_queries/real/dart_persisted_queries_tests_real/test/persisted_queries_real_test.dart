import 'dart:convert';
import 'dart:io';

import 'package:graphlink_persisted_queries_real_tests/generated/graphlink.dart';
import 'package:test/test.dart';

const _port = 9997;
const _graphql = 'http://localhost:$_port/graphql';

Future<Map<String, dynamic>> _control(String method, String path) async {
  final http = HttpClient();
  try {
    final request = await http.openUrl(method, Uri.parse('http://localhost:$_port/test/apq$path'));
    final response = await request.close();
    return jsonDecode(await utf8.decoder.bind(response).join()) as Map<String, dynamic>;
  } finally {
    http.close();
  }
}

Future<Map<String, dynamic>> _stats() => _control('GET', '');

GraphLinkClient _newClient() => GraphLinkClient.withHttp(url: _graphql, wsUrl: 'ws://localhost:$_port/graphql');

const _newUser = CreateUserInput(
  name: 'Persisted Pat',
  email: 'pat@test.com',
  status: UserStatus.active,
  address: AddressInput(street: 's', city: 'c', country: 'x'),
);

void main() {
  late GraphLinkClient client;

  setUp(() async {
    await _control('POST', '/reset');
    client = _newClient();
  });

  group('a long query', () {
    test('is registered on the first call: a GET miss, then a POST with the document', () async {
      final res = await client.queries.persistedLongQuery(id: 'user-1');

      expect(res.getUser.name, 'Alice Smith');
      final stats = await _stats();
      expect(stats['misses'], 1);
      expect(stats['registrations'], 1);
      expect(stats['stored'], 1);
      expect(stats['gets'], 1);
    });

    test('is a single GET hit once registered', () async {
      await client.queries.persistedLongQuery(id: 'user-1');

      final res = await client.queries.persistedLongQuery(id: 'user-1');

      expect(res.getUser.name, 'Alice Smith');
      final stats = await _stats();
      expect(stats['hits'], 1);
      expect(stats['registrations'], 1);
      expect(stats['gets'], 2);
    });

    test('a fresh client reuses what the server already stored', () async {
      await client.queries.persistedLongQuery(id: 'user-1');

      final res = await _newClient().queries.persistedLongQuery(id: 'user-1');

      expect(res.getUser.name, 'Alice Smith');
      final stats = await _stats();
      expect(stats['hits'], 1);
      expect(stats['registrations'], 1);
    });

    test('is registered again after the server evicts it', () async {
      await client.queries.persistedLongQuery(id: 'user-1');
      await _control('POST', '/evict');

      final res = await client.queries.persistedLongQuery(id: 'user-1');

      expect(res.getUser.name, 'Alice Smith');
      final stats = await _stats();
      expect(stats['registrations'], 2);
      expect(stats['stored'], 1);
    });

    test('still works when the server does not support persisted queries', () async {
      await _control('POST', '/supported/false');

      final first = await client.queries.persistedLongQuery(id: 'user-1');
      final second = await client.queries.persistedLongQuery(id: 'user-1');

      expect(first.getUser.name, 'Alice Smith');
      expect(second.getUser.name, 'Alice Smith');
      final stats = await _stats();
      expect(stats['stored'], 0);
      expect(stats['gets'], 1);
    });
  });

  group('a long mutation', () {
    test('is registered and sent over POST, never GET', () async {
      final res = await client.mutations.persistedLongMutation(input: _newUser);

      expect(res.createUser.name, 'Persisted Pat');
      final stats = await _stats();
      expect(stats['registrations'], 1);
      expect(stats['gets'], 0);
    });

    test('is a hash-only POST once registered', () async {
      await client.mutations.persistedLongMutation(input: _newUser);

      final res = await client.mutations.persistedLongMutation(input: _newUser);

      expect(res.createUser.email, 'pat@test.com');
      final stats = await _stats();
      expect(stats['hits'], 1);
      expect(stats['registrations'], 1);
      expect(stats['gets'], 0);
    });
  });

  test('a short query does not use persisted queries', () async {
    final res = await client.queries.persistedShortQuery();

    expect(res.listUsers, isNotEmpty);
    final stats = await _stats();
    expect(stats['hits'], 0);
    expect(stats['misses'], 0);
    expect(stats['registrations'], 0);
    expect(stats['gets'], 0);
  });
}
