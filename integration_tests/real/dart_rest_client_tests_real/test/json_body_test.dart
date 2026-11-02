import 'dart:convert';

import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'support.dart';
import 'package:test/test.dart';

void main() {
  late GraphLinkClient client;

  setUp(() async {
    await resetServer();
    client = newClient();
  });

  group('JSON body', () {
    test('the argument itself is the whole body, unwrapped', () async {
      final e = await client.mutations.eJson(body: ProductIn(name: 'Pen', price: 2.5, status: Status.archived, tags: ['a', 'b']));
      expect(e.method, 'POST');
      expect(e.path, '/echo/json');
      expect(e.contentType, startsWith('application/json'));
      final json = e.bodyJson as Map<String, dynamic>;
      expect(json['name'], 'Pen');
      expect(json['price'], 2.5);
      expect(json['status'], 'ARCHIVED');
      expect(json['tags'], ['a', 'b']);
      expect(json.containsKey('body'), isFalse);
    });

    test('a list argument is a JSON array', () async {
      final e = await client.mutations.eJsonList(body: [ProductIn(name: 'a'), ProductIn(name: 'b')]);
      final json = e.bodyJson as List;
      expect(json.map((j) => (j as Map)['name']), ['a', 'b']);
    });

    test('an empty list is still a body: []', () async {
      final e = await client.mutations.eJsonList(body: []);
      expect(e.bodyJson, isEmpty);
    });

    test('a null optional body means no body and no Content-Type', () async {
      final e = await client.mutations.eJsonOptional();
      expect(e.bodySize, 0);
      expect(e.contentType, isNull);
    });

    test('a present optional body is sent', () async {
      final e = await client.mutations.eJsonOptional(body: ProductIn(name: 'x'));
      expect((e.bodyJson as Map)['name'], 'x');
    });

    test('contentType on the operation replaces the default', () async {
      final e = await client.mutations.eJsonType(body: ProductIn(name: 'x'));
      expect(e.contentType, startsWith('application/vnd.test+json'));
    });

    test('non-ASCII text round-trips as UTF-8', () async {
      const name = 'é漢😀 "quoted" \\ back\nline';
      final e = await client.mutations.eJson(body: ProductIn(name: name));
      expect((e.bodyJson as Map)['name'], name);
      expect(e.bodySize, utf8.encode(e.bodyText!).length);
    });

    test('a large JSON body is delivered intact', () async {
      final tags = [for (var i = 0; i < 20000; i++) 'tag-$i'];
      final e = await client.mutations.eJson(body: ProductIn(name: 'big', tags: tags));
      expect(((e.bodyJson as Map)['tags'] as List).length, 20000);
    });

    test('POST/PUT/PATCH use their declared methods and path variables', () async {
      expect((await client.mutations.eJson(body: ProductIn(name: 'x'))).method, 'POST');
      final put = await client.mutations.ePut(id: 'a b', body: ProductIn(name: 'x'));
      expect([put.method, put.path], ['PUT', '/echo/put/a%20b']);
      final patch = await client.mutations.ePatch(id: 'p', body: ProductIn(name: 'x'));
      expect([patch.method, patch.path], ['PATCH', '/echo/patch/p']);
    });

    test('path, header and body roles combine in one request', () async {
      final e = await client.mutations.eHeaderBody(id: 'i1', tenant: 'acme', body: ProductIn(name: 'x'));
      expect(e.path, '/echo/hb/i1');
      expect(e.header('x-tenant'), 'acme');
      expect((e.bodyJson as Map)['name'], 'x');
    });
  });
}
