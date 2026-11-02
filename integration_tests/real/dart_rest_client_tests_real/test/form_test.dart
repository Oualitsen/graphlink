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

  group('form body', () {
    test('is application/x-www-form-urlencoded and carries scalars', () async {
      final e = await client.mutations.eForm(name: 'Pen', n: 3);
      expect(e.method, 'POST');
      expect(e.contentType, startsWith('application/x-www-form-urlencoded'));
      expect(e.formPairs, ['name=Pen', 'n=3']);
    });

    test('values with reserved characters are encoded and decode back', () async {
      const value = 'a&b=c d+e%f/é😀\n';
      final e = await client.mutations.eForm(name: value);
      expect(e.formValue('name'), value);
    });

    test('lists repeat the key (or join with commas)', () async {
      final e = await client.mutations.eForm(name: 'n', tags: ['x', 'y z']);
      expect(e.formPairs, ['name=n', ...variant.list('tags', ['x', 'y z'])]);
    });

    test('FLAT nests objects with the configured separator', () async {
      final e = await client.mutations.eForm(name: 'n', meta: Meta(name: 'm', address: Address(city: 'Oran')));
      expect(e.formPairs, [
        'name=n',
        '${variant.key('meta', ['name'])}=m',
        '${variant.key('meta', ['address', 'city'])}=Oran',
      ]);
    });

    test('SPREAD puts the fields at the top level', () async {
      final e = await client.mutations.eForm(name: 'n', filter: Filter(tag: 't', minPrice: 1));
      expect(e.formPairs, ['name=n', 'tag=t', 'minPrice=1.0']);
    });

    test('JSON encoding sends one entry holding the JSON text', () async {
      final e = await client.mutations.eForm(name: 'n', asJson: Meta(name: 'm'));
      expect((jsonDecode(e.formValue('j')!) as Map)['name'], 'm');
    });

    test('null fields are omitted', () async {
      final e = await client.mutations.eForm(name: 'n');
      expect(e.formPairs, ['name=n']);
    });

    test('when every field is null the request has no body and no Content-Type', () async {
      final e = await client.mutations.eFormEmpty();
      expect(e.bodySize, 0);
      expect(e.contentType, isNull);
    });

    test('a single present field sends a body', () async {
      final e = await client.mutations.eFormEmpty(b: 0);
      expect(e.formPairs, ['b=0']);
    });
  });
}
