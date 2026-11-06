import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late GraphLinkClient client;

  setUp(() async {
    await resetServer();
    client = newClient();
  });

  group('nested', () {
    test('interface and union fields inside an object', () async {
      final kennel = await client.queries.kennel();
      expect(kennel.resident, isA<Dog>());
      expect((kennel.resident as Dog).barks, isTrue);
      expect(kennel.hit, isA<Product>());
      expect((kennel.hit as Product).name, 'Pen');
    });

    test('lists of interfaces and unions inside an object', () async {
      final kennel = await client.queries.kennel();
      expect(kennel.featured.map((p) => p.runtimeType), [Dog, Cat]);
      expect((kennel.featured[1] as Cat).lives, 9);
      expect(kennel.hits!.map((h) => h.runtimeType), [Product, Owner]);
    });

    test('null elements in a list of interfaces', () async {
      final mixed = (await client.queries.kennel()).mixed!;
      expect(mixed, hasLength(3));
      expect(mixed[0], isA<Dog>());
      expect(mixed[1], isNull);
      expect(mixed[2], isA<Cat>());
    });

    test('null polymorphic fields', () async {
      final empty = (await client.queries.shelter()).kennels[1];
      expect(empty.resident, isNull);
      expect(empty.featured, isEmpty);
      expect(empty.mixed, isNull);
      expect(empty.hit, isNull);
      expect(empty.hits, isNull);
    });

    test('two levels deep', () async {
      final shelter = await client.queries.shelter();
      expect(shelter.kennels, hasLength(2));
      expect(shelter.kennels[0].resident, isA<Dog>());
      expect((shelter.kennels[0].featured[1] as Cat).name, 'Tom');
    });
  });

  group('results', () {
    test('[Pet]! keeps null elements', () async {
      final pets = await client.queries.petsNullable();
      expect(pets, hasLength(3));
      expect(pets[0], isA<Dog>());
      expect(pets[1], isNull);
      expect(pets[2], isA<Cat>());
    });

    test('[Pet!] decodes a JSON null as null', () async {
      expect(await client.queries.petsOptional(), isNull);
    });

    test('through responsePath', () async {
      final pets = await client.queries.petsWrapped();
      expect(pets.map((p) => p.runtimeType), [Dog, Cat]);
    });

    test('from a mutation', () async {
      final pet = await client.mutations.adoptPet(id: 'c9');
      expect(pet, isA<Cat>());
      expect(pet.id, 'c9');
      expect(pet.name, 'Adopted');
    });

    test('from a cached operation', () async {
      final first = await client.queries.cachedPet(id: 'd7');
      final second = await client.queries.cachedPet(id: 'd7');
      expect(first, isA<Dog>());
      expect(first!.name, 'Rex1');
      expect(second!.name, 'Rex1');
      expect((await client.queries.cachedPet(id: 'd8'))!.name, 'Rex1');
    });
  });

  group('payload problems', () {
    test('discriminator key absent', () async {
      await expectLater(
        client.queries.petNoKind(),
        throwsA(predicate((e) => e.toString().contains('Pet') && e.toString().contains('kind'))),
      );
    });

    test('discriminator null', () async {
      await expectLater(
        client.queries.petNullKind(),
        throwsA(predicate((e) => e.toString().contains('Pet') && e.toString().contains('kind'))),
      );
    });

    test('unknown keys inside a member are ignored', () async {
      final pet = await client.queries.petExtraKeys();
      expect(pet, isA<Dog>());
      expect((pet as Dog).name, 'Rex');
    });

    test('a member missing a required field names the field', () async {
      await expectLater(
        client.queries.petMissingField(),
        throwsA(predicate((e) => e.toString().contains('barks'))),
      );
    });
  });
}
