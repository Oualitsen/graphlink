import { describe, test, expect } from 'vitest';
import { newClient } from './fixtures.js';

describe('hoist args', () => {
  const client = newClient();

  test('many required hoisted args (input renamed CatalogFieldArgs1 on collision)', async () => {
    const catalog = (await client.queries.catalog({
      fieldArgs: { productsCategory: 'books', productsLimit: 3, productsOffset: 0 },
    })).catalog;
    expect(catalog.products).toHaveLength(3);
    expect(catalog.products.every(p => p.name.startsWith('books'))).toBe(true);
  });

  test('all-optional hoisted args can be omitted (default itemsLimit=10)', async () => {
    const feed = (await client.queries.feed({})).feed;
    expect(feed.items).toHaveLength(10);
  });

  test('optional hoisted args can be supplied', async () => {
    const feed = (await client.queries.feed({
      fieldArgs: { itemsLimit: 4, itemsSort: 'z' },
    })).feed;
    expect(feed.items).toHaveLength(4);
    expect(feed.items[0].name.startsWith('z')).toBe(true);
  });

  test('nested-depth hoisting collapses into one input', async () => {
    const store = (await client.queries.store({
      fieldArgs: { shelvesFloor: 2, productsLimit: 3 },
    })).store;
    expect(store.shelves).toHaveLength(2);
    expect(store.shelves[0].products).toHaveLength(3);
  });

  test('param-name collision uses fieldArgs1 for the synthetic arg', async () => {
    const search = (await client.queries.search({
      fieldArgs: 'q',
      fieldArgs1: { hitsLimit: 3 },
    })).search;
    expect(search.id).toBe('q');
    expect(search.hits).toHaveLength(3);
  });
});
