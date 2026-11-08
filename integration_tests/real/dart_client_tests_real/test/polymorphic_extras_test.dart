import 'package:graphlink_client_integration_tests/generated/graphlink.dart';
import 'package:test/test.dart';

import 'real_server_adapter.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('nested lists of polymorphic types', () {
    test('lists of lists of unions and interfaces', () async {
      final grid = (await client.queries.grid()).grid;
      expect(grid.cells.map((row) => row?.map((a) => a?.runtimeType).toList()), [
        [Photo, null],
        [Video],
        <Type>[],
      ]);
      expect(grid.rows.map((row) => row.map((e) => e.runtimeType).toList()), [
        [Article, Comment],
        [Article],
      ]);
      expect(grid.maybe!.single!.map((a) => a.runtimeType), [Photo, Document]);
    });

    test('empty and null lists stay as they are', () async {
      final grid = (await client.queries.grid(empty: true)).grid;
      expect(grid.cells, isEmpty);
      expect(grid.rows, isEmpty);
      expect(grid.maybe, isNull);
    });

    test('a projected selection of nested lists', () async {
      final grid = (await client.queries.gridProjected()).grid.toJson();
      final cells = grid['cells'] as List;
      expect((cells[0] as List)[0]['width'], 640);
      expect((cells[0] as List)[1], isNull);
      expect((cells[1] as List)[0]['seconds'], 30);
      expect(cells[2], isEmpty);
      final rows = grid['rows'] as List;
      expect((rows[0] as List).map((e) => e['id']), ['a1', 'c1']);
      expect((rows[0] as List)[0]['title'], 'Hello');
      expect((rows[0] as List)[1]['text'], 'Nice');
      expect(((grid['maybe'] as List)[0] as List).map((a) => a['url'] ?? a['id']), ['http://cdn/1.png', 'd1']);
    });
  });

  group('custom scalars inside polymorphic types', () {
    test('a list of a union with scalar fields', () async {
      final moments = (await client.queries.moments()).moments;
      final stamp = moments[0] as Stamp;
      expect(stamp.at, '2026-01-02T03:04:05Z');
      expect(stamp.big, 4294967296);
      final span = moments[1] as Span;
      expect(span.until, '2026-02-04');
      expect(span.opaque, 'opaque:o-9');
      expect(span.dts, ['2026-03-04T05:06:07Z']);
    });

    test('a list of an interface with scalar fields', () async {
      final timed = (await client.queries.timed()).timed;
      expect(timed.map((t) => t.runtimeType), [Span, Stamp]);
      expect((timed[0] as Span).opaque, 'opaque:o-9');
      expect((timed[1] as Stamp).big, 4294967296);
    });

    test('a projected union keeps the scalars it selects', () async {
      final moments = (await client.queries.momentsProjected()).moments;
      expect((moments[0] as dynamic).at, '2026-01-02T03:04:05Z');
      expect((moments[0] as dynamic).big, 4294967296);
      expect((moments[1] as dynamic).opaque, 'opaque:o-9');
      expect((moments[1] as dynamic).until, '2026-02-04');
    });

    test('an interface selection shares the interface scalar', () async {
      final timed = (await client.queries.timedProjected()).timed;
      expect(timed.map((t) => (t as dynamic).at), ['2026-02-03T04:05:06Z', '2026-01-02T03:04:05Z']);
      expect((timed[0] as dynamic).opaque, 'opaque:o-9');
      expect((timed[1] as dynamic).big, 4294967296);
    });
  });

  group('a union member that points back at its union', () {
    test('three levels deep', () async {
      final chain = (await client.queries.chainDeep(id: 'l1')).chain as dynamic;
      expect(chain.id, 'l1');
      expect(chain.next.id, 'l2');
      expect(chain.next.next.id, 'e1');
      expect(chain.next.next.reason, 'done');
    });

    test('the end of the chain directly, and an unknown id', () async {
      expect(((await client.queries.chainDeep(id: 'e1')).chain as dynamic).reason, 'done');
      expect((await client.queries.chainDeep(id: 'nope')).chain, isNull);
    });

    test('the generated all-fields selection stops after one level', () async {
      final chain = (await client.queries.chain(id: 'l1')).chain as dynamic;
      expect(chain.id, 'l1');
      expect(chain.next.id, 'l2');
    });
  });

  group('lists of unions and interfaces in every operation kind', () {
    test('a cached list is served once and fetched again after its tag is evicted', () async {
      var calls = 0;
      final real = httpAdapterForPort(9999);
      final counting = GraphLinkClient(
        adapter: (payload) {
          calls++;
          return real(payload);
        },
        wsAdapter: DefaultGraphLinkWebSocketAdapter(url: 'ws://localhost:9999/graphql'),
      );
      final first = (await counting.queries.cachedAttachments()).cachedAttachments;
      final second = (await counting.queries.cachedAttachments()).cachedAttachments;
      expect(calls, 1);
      expect(first.map((a) => a.runtimeType), [Photo, Video, Document]);
      expect((second[1] as Video).seconds, (first[1] as Video).seconds);

      await counting.mutations.evictAttachments();
      final third = (await counting.queries.cachedAttachments()).cachedAttachments;
      expect(calls, 3);
      expect((third[1] as Video).seconds, isNot((first[1] as Video).seconds));
    });

    test('an error on a list of unions throws and a good call still works', () async {
      await expectLater(client.queries.failingAttachments(fail: true), throwsA(anything));
      expect((await client.queries.failingAttachments(fail: false)).failingAttachments, hasLength(3));
    });

    test('a mutation returning a list of unions', () async {
      final five = (await client.mutations.bulkAttachments(n: 5)).bulkAttachments;
      expect(five.map((a) => a.runtimeType), [Photo, Video, Document, Photo, Video]);
      expect((await client.mutations.bulkAttachments(n: 0)).bulkAttachments, isEmpty);
    });

    test('a mutation returning a list of an interface', () async {
      final entities = (await client.mutations.bulkEntities()).bulkEntities;
      expect(entities.map((e) => e.runtimeType), [Article, Comment, Article]);
    });

    test('a subscription emitting lists of unions', () async {
      final batches = await client.subscriptions.attachmentsBatch().take(2).toList().timeout(const Duration(seconds: 10));
      expect(batches[0].attachmentsBatch.map((a) => a.runtimeType), [Photo, Video, Document]);
      expect(batches[1].attachmentsBatch.map((a) => a.runtimeType), [Document]);
    });

    test('a subscription emitting a list of an interface', () async {
      final batch = await client.subscriptions.entityBatch().first.timeout(const Duration(seconds: 10));
      expect(batch.entityBatch.map((e) => e.runtimeType), [Article, Comment]);
    });
  });

  group('@oneOf inputs with richer members', () {
    Future<String> pick(Pick p) async => (await client.queries.describePick(pick: p)).describePick;

    test('an input object', () async {
      expect(await pick(const Pick(inner: InnerInput(n: 5, label: 'x', tags: ['t']))), '{inner={label=x, n=5, tags=[t]}}');
    });

    test('an enum', () async {
      expect(await pick(const Pick(status: UserStatus.suspended)), '{status=SUSPENDED}');
    });

    test('a list, including an empty one', () async {
      expect(await pick(const Pick(ids: [1, 2])), '{ids=[1, 2]}');
      expect(await pick(const Pick(ids: [])), '{ids=[]}');
    });

    test('another oneOf input', () async {
      expect(await pick(const Pick(pet: Pet(cat: 'Tom'))), '{pet={cat=Tom}}');
    });

    test('itself, nested', () async {
      expect(await pick(const Pick(child: Pick(child: Pick(pet: Pet(dog: 3))))), '{child={child={pet={dog=3}}}}');
    });

    test('a list of oneOf inputs inside a regular input', () async {
      final both = await client.queries.describeBasket(basket: const Basket(pets: [Pet(cat: 'a'), Pet(dog: 2)], lead: Pet(dog: 3)));
      expect(both.describeBasket, '{lead={dog=3}, pets=[{cat=a}, {dog=2}]}');
      final noLead = await client.queries.describeBasket(basket: const Basket(pets: [Pet(cat: 'a'), Pet(dog: 2)]));
      expect(noLead.describeBasket, '{pets=[{cat=a}, {dog=2}]}');
      expect((await client.queries.describeBasket(basket: const Basket(pets: []))).describeBasket, '{pets=[]}');
    });
  });
}
