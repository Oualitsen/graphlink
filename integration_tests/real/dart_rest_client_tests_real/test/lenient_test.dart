import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'support.dart';
import 'package:test/test.dart';

void main() {
  late GraphLinkClient client;

  setUp(() async {
    await resetServer();
    client = newClient();
  });

  test('null and missing fields of non-null schema fields decode as null', () async {
    final product = await client.queries.lenientProduct();
    expect(product.id, 'p1');
    expect(product.name, isNull);
    expect(product.price, isNull);
    expect(product.tags, isNull);
  });

  test('nested objects are lenient too', () async {
    final related = (await client.queries.lenientProduct()).related!;
    expect(related, hasLength(2));
    expect(related[0].id, 'p2');
    expect(related[0].name, isNull);
    expect(related[0].related, isNull);
    expect(related[1].name, 'Three');
    expect(related[1].price, 3.5);
    expect(related[1].related, isNull);
  });

  test('lists of objects decode', () async {
    final products = await client.queries.lenientProducts();
    expect(products, hasLength(2));
    expect(products[0].name, isNull);
    expect(products[1].name, 'B');
  });

  test('an empty body is still null because the schema says so', () async {
    expect(await client.queries.lenientNothing(), isNull);
  });

  test('the same type without the directive still fails on the same payload', () async {
    await expectLater(
      client.queries.strictProduct(),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', 'Product.name is missing or null in the response')),
    );
  });

  test('interfaces decode through their discriminator with missing fields', () async {
    final pets = await client.queries.lenientPets();
    expect(pets, hasLength(3));

    final first = pets[0] as DogRest;
    expect(first.id, 'd1');
    expect(first.name, isNull);
    expect(first.barks, isNull);

    final second = pets[1] as CatRest;
    expect(second.id, 'c1');
    expect(second.name, isNull);
    expect(second.lives, isNull);

    final third = pets[2] as DogRest;
    expect(third.id, isNull);
    expect(third.name, 'Rex');
    expect(third.barks, isTrue);
  });

  test('the interface without the directive still fails on the same payload', () async {
    await expectLater(
      client.queries.strictPets(),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', endsWith('is missing or null in the response'))),
    );
  });

  test('unions decode through their discriminator', () async {
    final hits = await client.queries.lenientHits();
    expect((hits[0] as ProductRest).id, 'p1');
    final owner = hits[1] as OwnerRest;
    expect(owner.id, 'o1');
    expect(owner.name, isNull);
  });

  test('a cached lenient result is stored and decoded the same way', () async {
    final cached = newClient(store: InMemoryGraphLinkCacheStore());
    final first = await cached.queries.lenientCached();
    final second = await cached.queries.lenientCached();
    expect(first.name, isNull);
    expect(second.name, isNull);
    expect(second.related, hasLength(first.related!.length));
    expect(second.related![1].name, 'Three');
  });
}
