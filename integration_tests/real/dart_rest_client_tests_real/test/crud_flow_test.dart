import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'support.dart';
import 'package:test/test.dart';

void main() {
  late GraphLinkClient client;

  setUp(() async {
    await resetServer();
    client = newClient();
  });

  group('a realistic product lifecycle', () {
    test('create, read, list, update, rename, gallery, delete', () async {
      final created = await client.mutations.createProduct(input: ProductIn(name: 'Lamp', price: 30, tags: ['home']));
      expect(created.name, 'Lamp');
      expect(created.status, Status.active);

      final fetched = (await client.queries.product(id: created.id))!;
      expect(fetched.price, 30);

      final byTag = await client.queries.products(filter: Filter(tag: 'home'));
      expect(byTag.map((p) => p.id), [created.id]);

      final byIds = await client.queries.products(ids: ['p1', created.id]);
      expect(byIds.map((p) => p.id).toSet(), {'p1', created.id});

      final patched = await client.mutations.patchProduct(id: created.id, input: ProductIn(name: 'Lamp 2', price: 35));
      expect([patched.name, patched.price], ['Lamp 2', 35]);

      final renamed = await client.mutations.renameProduct(id: created.id, name: 'Lamp 3', note: 'n');
      expect([renamed.name, renamed.tags], ['Lamp 3', ['n']]);

      final gallery = await client.mutations.gallery(
        id: created.id,
        title: 'Gallery é',
        files: [uploadOf(pattern(100), filename: 'a.png'), uploadOf(pattern(200), filename: 'b.png')],
      );
      expect([gallery.name, gallery.tags], ['Gallery é', ['a.png', 'b.png']]);

      final replaced = await client.mutations.replaceProduct(id: created.id, input: ProductIn(name: 'Final'));
      expect(replaced.name, 'Final');

      await client.mutations.deleteProduct(id: created.id);
      await expectLater(client.queries.product(id: created.id), throwsA(isA<RestError>().having((e) => e.status, 'status', 404)));
    });

    test('Void succeeds on 204 and fails with RestError on a missing resource', () async {
      await client.mutations.deleteProduct(id: 'p2');
      await expectLater(client.mutations.deleteProduct(id: 'p2'), throwsA(isA<RestError>().having((e) => e.status, 'status', 404)));
    });

    test('the same client serves many concurrent calls correctly', () async {
      final results = await Future.wait([
        for (var i = 0; i < 40; i++) client.mutations.createProduct(input: ProductIn(name: 'item-$i')),
      ]);
      expect(results.map((p) => p.name).toSet().length, 40);
      expect(results.map((p) => p.id).toSet().length, 40);
      final listed = await client.queries.products();
      expect(listed.length, 42);
    });

    test('products list with no filters sends no query', () async {
      expect((await client.queries.products()).map((p) => p.id), ['p1', 'p2']);
    });
  });
}
