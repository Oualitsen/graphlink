import 'package:test/test.dart';
import 'package:graphlink_server_integration_tests_dart_client/generated/graphlink.dart';
import 'fixtures.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  test('many required hoisted args (input renamed CatalogFieldArgs1 on collision)',
      () async {
    final catalog = (await client.queries.catalog(
      fieldArgs: const CatalogFieldArgs1(
          productsCategory: 'books', productsLimit: 3, productsOffset: 0),
    ))
        .catalog;
    expect(catalog.products, hasLength(3));
    expect(catalog.products.every((p) => p.name.startsWith('books')), isTrue);
  });

  test('all-optional hoisted args can be omitted (default itemsLimit=10)',
      () async {
    final feed = (await client.queries.feed()).feed;
    expect(feed.items, hasLength(10));
  });

  test('optional hoisted args can be supplied', () async {
    final feed = (await client.queries
            .feed(fieldArgs: const FeedFieldArgs(itemsLimit: 4, itemsSort: 'z')))
        .feed;
    expect(feed.items, hasLength(4));
    expect(feed.items.first.name.startsWith('z'), isTrue);
  });

  test('nested-depth hoisting collapses into one input', () async {
    final store = (await client.queries.store(
      fieldArgs: const StoreFieldArgs(shelvesFloor: 2, productsLimit: 3),
    ))
        .store;
    expect(store.shelves, hasLength(2));
    expect(store.shelves.first.products, hasLength(3));
  });

  test('param-name collision uses fieldArgs1 for the synthetic arg', () async {
    final search = (await client.queries.search(
      fieldArgs: 'q',
      fieldArgs1: const SearchFieldArgs(hitsLimit: 3),
    ))
        .search;
    expect(search.id, 'q');
    expect(search.hits, hasLength(3));
  });
}
