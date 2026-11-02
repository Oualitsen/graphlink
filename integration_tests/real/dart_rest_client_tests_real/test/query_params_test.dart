import 'dart:convert';

import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'support.dart';
import 'variant.dart';
import 'package:test/test.dart';

void main() {
  late GraphLinkClient client;

  setUp(() async {
    await resetServer();
    client = newClient();
  });

  group('scalars and paths', () {
    test('every scalar kind is a query value; defaults are sent; nulls are omitted', () async {
      final e = await client.queries
          .eScalars(id: 'x1', s: 'hello', i: 3, f: 2.5, b: true, st: Status.archived, renamed: 'r');
      expect(e.method, 'GET');
      expect(e.path, '/echo/scalars/x1');
      expect(e.queryPairs, ['s=hello', 'i=3', 'f=2.5', 'b=true', 'st=ARCHIVED', 'dflt=5', 'x-ren=r']);
      expect(e.bodySize, 0);
      expect(e.contentType, isNull);
      expect(e.header('accept'), 'application/json');
    });

    test('an omitted optional is absent, a default still goes out, an explicit value replaces it', () async {
      expect((await client.queries.eScalars(id: 'x1')).queryPairs, ['dflt=5']);
      expect((await client.queries.eScalars(id: 'x1', dflt: 9)).queryPairs, ['dflt=9']);
    });

    test('false and 0 are values, not omissions', () async {
      final e = await client.queries.eScalars(id: 'x1', b: false, i: 0, s: '');
      expect(e.queryPairs, ['s=', 'i=0', 'b=false', 'dflt=5']);
    });

    test('path segments and query values survive reserved and non-ASCII characters', () async {
      const segment = 'a b/c?d#é+%';
      const value = 'a&b=c d+e/é"%25';
      final e = await client.queries.eSpecial(segment: segment, q: value, other: 'ü');
      expect(e.path, '/echo/special/${Uri.encodeComponent(segment)}/tail');
      expect(e.queryValue('q'), value);
      expect(e.queryValue('other'), 'ü');
    });

    test('an empty string path segment is not silently dropped', () async {
      final e = await client.queries.eSpecial(segment: 'seg', q: '');
      expect(e.queryValue('q'), '');
    });

    test('DELETE carries its arguments in the query and sends no body', () async {
      final e = await client.queries.eDeleteQuery(id: 'd1', force: true);
      expect(e.method, 'DELETE');
      expect(e.path, '/echo/delete/d1');
      expect(e.queryPairs, ['force=true']);
      expect(e.bodySize, 0);
    });
  });

  group('lists', () {
    test('scalar lists repeat the key (or join with commas); empty lists send nothing', () async {
      final e = await client.queries.eLists(tags: ['a', 'b c'], ids: [1, 2, 3], empty: []);
      expect(e.queryPairs, [...variant.list('tags', ['a', 'b c']), ...variant.list('ids', ['1', '2', '3'])]);
      expect(e.queryValue('empty'), isNull);
    });

    test('a matrix uses indexed keys at both levels', () async {
      final e = await client.queries.eLists(matrix: [
        [1, 2],
        [3],
      ]);
      expect(e.queryPairs, [
        '${variant.key('matrix', [0, 0])}=1',
        '${variant.key('matrix', [0, 1])}=2',
        '${variant.key('matrix', [1, 0])}=3',
      ]);
    });

    test('a list of objects uses indexed keys and scalar lists inside objects repeat', () async {
      final e = await client.queries.eLists(rows: [
        Row(name: 'r0', ids: [1, 2]),
        Row(name: 'r1'),
      ]);
      expect(e.queryPairs, [
        '${variant.key('rows', [0, 'name'])}=r0',
        ...variant.list(variant.key('rows', [0, 'ids']), ['1', '2']),
        '${variant.key('rows', [1, 'name'])}=r1',
      ]);
    });

    test('list items with reserved characters round-trip', () async {
      final e = await client.queries.eLists(tags: ['a&b', 'c=d', 'e f', 'é']);
      expect(variant.comma ? e.queryValue('tags') : e.query.where((p) => p.name == 'tags').map((p) => p.value).join('|'),
          variant.comma ? 'a&b,c=d,e f,é' : 'a&b|c=d|e f|é');
    });
  });

  group('objects', () {
    test('an input is spread by default: one key per field, the argument name is not sent', () async {
      final e = await client.queries.eObjects(filter: Filter(tag: 'x', minPrice: 3, status: Status.active));
      expect(e.queryPairs, ['tag=x', 'minPrice=3.0', 'status=ACTIVE']);
    });

    test('a spread input with unset fields sends only the set ones', () async {
      final e = await client.queries.eObjects(filter: Filter(tag: 'x'));
      expect(e.queryPairs, ['tag=x']);
    });

    test('FLAT nests with the configured separator, at any depth', () async {
      final e = await client.queries.eObjects(
        meta: Meta(
          name: 'm',
          tags: ['t1', 't2'],
          address: Address(city: 'Oran', street: 'Rue 1', geo: Geo(lat: 35.7, lng: -0.6)),
        ),
      );
      expect(e.queryPairs, [
        '${variant.key('meta', ['name'])}=m',
        ...variant.list(variant.key('meta', ['tags']), ['t1', 't2']),
        '${variant.key('meta', ['address', 'city'])}=Oran',
        '${variant.key('meta', ['address', 'street'])}=Rue 1',
        '${variant.key('meta', ['address', 'geo', 'lat'])}=35.7',
        '${variant.key('meta', ['address', 'geo', 'lng'])}=-0.6',
      ]);
    });

    test('encoding JSON sends one key holding the JSON text', () async {
      final e = await client.queries.eObjects(asJson: Meta(name: 'm', tags: ['a'], address: Address(city: 'c')));
      expect(e.query.map((p) => p.name), ['j']);
      final json = jsonDecode(e.queryValue('j')!) as Map<String, dynamic>;
      expect(json['name'], 'm');
      expect(json['tags'], ['a']);
      expect((json['address'] as Map)['city'], 'c');
    });

    test('several roles in one call keep their own keys', () async {
      final e = await client.queries.eObjects(filter: Filter(tag: 'x'), meta: Meta(name: 'm'), asJson: Meta(name: 'j'));
      expect(e.query.map((p) => p.name).toSet(), {'tag', variant.key('meta', ['name']), 'j'});
    });
  });
}
