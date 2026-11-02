import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'support.dart';
import 'package:test/test.dart';

void main() {
  late GraphLinkClient client;

  setUp(() async {
    await resetServer();
    client = newClient();
  });

  group('status handling', () {
    test('200 and 201 decode the body', () async {
      expect((await client.queries.status(code: 200))!.name, 'Pen');
      expect((await client.queries.status(code: 201))!.id, 'p1');
    });

    test('204 is null for a nullable result and a decode error for a non-null one', () async {
      expect(await client.queries.status(code: 204), isNull);
      await expectLater(client.queries.statusNonNull(code: 204), throwsFormatException);
    });

    for (final code in [400, 401, 403, 404, 409, 422, 500, 502, 503]) {
      test('$code raises RestError with status, headers and body', () async {
        await expectLater(
          client.queries.status(code: code),
          throwsA(isA<RestError>()
              .having((e) => e.status, 'status', code)
              .having((e) => e.body, 'body', contains('status $code'))
              .having((e) => e.headers['x-reason'], 'x-reason', 'reason-$code')),
        );
      });
    }

    test('an error status is never turned into null, even for a nullable result', () async {
      await expectLater(client.queries.status(code: 404), throwsA(isA<RestError>()));
    });

    test('a RestError is catchable by type and prints its status', () async {
      try {
        await client.queries.status(code: 418);
        fail('should throw');
      } on RestError catch (e) {
        expect(e.toString(), contains('418'));
      }
    });

    test('a failed call does not poison the connection for the next one', () async {
      await expectLater(client.queries.status(code: 500), throwsA(isA<RestError>()));
      expect((await client.queries.status(code: 200))!.id, 'p1');
    });
  });

  group('empty bodies', () {
    test('an empty 200 is null when nullable and an error when not', () async {
      expect(await client.queries.blank(), isNull);
      await expectLater(client.queries.blankNonNull(), throwsFormatException);
    });

    test('204 is null when nullable', () async {
      expect(await client.queries.noContent(), isNull);
      expect(await client.queries.textOptional(), isNull);
    });

    test('a JSON null literal is null when nullable', () async {
      expect(await client.queries.jsonNull(), isNull);
    });
  });

  group('value kinds', () {
    test('scalars', () async {
      expect(await client.queries.count(), 7);
      expect(await client.queries.flag(), isTrue);
    });

    test('TEXT is returned verbatim, decoded as UTF-8', () async {
      expect(await client.queries.text(), 'héllo ✓');
    });

    test('responsePath selects a nested value', () async {
      expect(await client.queries.deep(), [1, 2, 3]);
      final items = await client.queries.wrapped();
      expect(items.map((p) => p.id), ['p1', 'p2']);
    });

    test('non-ASCII JSON text decodes correctly', () async {
      final p = await client.queries.unicode();
      expect(p.name, 'é漢😀 "quoted"');
      expect(p.tags, ['ß']);
    });

    test('unknown JSON keys are ignored and a null list stays null', () async {
      final p = await client.queries.extraKeys();
      expect(p.id, 'x');
      expect(p.tags, isNull);
    });

    test('a missing non-null field is a decode error naming the type and field', () async {
      await expectLater(
        client.queries.missingField(),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', 'Product.name is missing or null in the response')),
      );
    });

    test('nested types, enums and cyclic references decode', () async {
      final p = (await client.queries.product(id: 'p1'))!;
      expect(p.status, Status.active);
      expect(p.related!.single.name, 'Book');
      expect(p.related!.single.related, isNull);
    });
  });

  group('polymorphism', () {
    test('an interface decodes through the discriminator field', () async {
      final pets = await client.queries.pets();
      expect(pets[0], isA<Dog>());
      expect((pets[0] as Dog).barks, isTrue);
      expect(pets[1], isA<Cat>());
      expect((pets[1] as Cat).lives, 9);
    });

    test('a single interface value', () async {
      final pet = await client.queries.pet(id: 'c1');
      expect(pet, isA<Cat>());
      expect(pet!.name, 'Tom');
    });

    test('an unknown discriminator value is an error naming the parent and the value', () async {
      await expectLater(client.queries.petsUnknown(), throwsA(predicate((e) => e.toString().contains('bird'))));
    });

    test('a union decodes through its discriminator values map', () async {
      final hits = await client.queries.hits();
      expect(hits[0], isA<Product>());
      expect(hits[1], isA<Owner>());
    });
  });

  group('GraphQL and REST on one client', () {
    test('a GraphQL query and REST operations are served by the same client', () async {
      expect((await client.queries.getCount()).getCount, 19);
      expect(await client.queries.count(), 7);
      expect((await client.queries.getCount()).getCount, 19);
    });
  });
}
