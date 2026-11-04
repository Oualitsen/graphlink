import { beforeEach, describe, expect, it } from 'vitest';
import { InMemoryGraphLinkCacheStore, type CatRest, type DogRest, type GraphLinkClient, type OwnerRest, type ProductRest } from '../lib/generated/graphlink';
import { newClient, resetServer } from './support';

let client: GraphLinkClient;

beforeEach(async () => {
  await resetServer();
  client = newClient();
});

const absent = (value: unknown) => value ?? null;

describe('lenient copies', () => {
  it('null and missing fields of non-null schema fields decode as null', async () => {
    const product = await client.queries.lenientProduct();
    expect(product.id).toBe('p1');
    expect(absent(product.name)).toBeNull();
    expect(absent(product.price)).toBeNull();
    expect(absent(product.tags)).toBeNull();
  });

  it('nested objects are lenient too', async () => {
    const related = (await client.queries.lenientProduct()).related!;
    expect(related).toHaveLength(2);
    expect(related[0].id).toBe('p2');
    expect(absent(related[0].name)).toBeNull();
    expect(absent(related[0].related)).toBeNull();
    expect(related[1].name).toBe('Three');
    expect(related[1].price).toBe(3.5);
    expect(absent(related[1].related)).toBeNull();
  });

  it('lists of objects decode', async () => {
    const products: ProductRest[] = await client.queries.lenientProducts();
    expect(products).toHaveLength(2);
    expect(absent(products[0].name)).toBeNull();
    expect(products[1].name).toBe('B');
  });

  it('an empty body is still null because the schema says so', async () => {
    expect(await client.queries.lenientNothing()).toBeNull();
  });

  it('the same type without the directive still fails on the same payload', async () => {
    await expect(client.queries.strictProduct()).rejects.toThrow('Product.name is missing or null in the response');
  });

  it('interfaces decode through their discriminator with missing fields', async () => {
    const pets = await client.queries.lenientPets();
    expect(pets).toHaveLength(3);

    const first = pets[0] as DogRest;
    expect(first.__typename).toBe('DogRest');
    expect(first.id).toBe('d1');
    expect(absent(first.name)).toBeNull();
    expect(absent(first.barks)).toBeNull();

    const second = pets[1] as CatRest;
    expect(second.__typename).toBe('CatRest');
    expect(second.id).toBe('c1');
    expect(absent(second.name)).toBeNull();
    expect(absent(second.lives)).toBeNull();

    const third = pets[2] as DogRest;
    expect(absent(third.id)).toBeNull();
    expect(third.name).toBe('Rex');
    expect(third.barks).toBe(true);
  });

  it('the interface without the directive still fails on the same payload', async () => {
    await expect(client.queries.strictPets()).rejects.toThrow(/is missing or null in the response$/);
  });

  it('unions decode through their discriminator', async () => {
    const hits = await client.queries.lenientHits();
    expect(hits[0].__typename).toBe('ProductRest');
    expect((hits[0] as ProductRest).id).toBe('p1');
    const owner = hits[1] as OwnerRest;
    expect(owner.__typename).toBe('OwnerRest');
    expect(owner.id).toBe('o1');
    expect(absent(owner.name)).toBeNull();
  });

  it('a cached lenient result is stored and decoded the same way', async () => {
    const cached = newClient({ store: new InMemoryGraphLinkCacheStore() });
    const first = await cached.queries.lenientCached();
    const second = await cached.queries.lenientCached();
    expect(absent(first.name)).toBeNull();
    expect(absent(second.name)).toBeNull();
    expect(second.related).toHaveLength(first.related!.length);
    expect(second.related![1].name).toBe('Three');
  });
});
