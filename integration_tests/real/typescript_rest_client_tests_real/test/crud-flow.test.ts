import { beforeEach, describe, expect, it } from 'vitest';
import { RestError, Status, type GraphLinkClient } from '../lib/generated/graphlink';
import { newClient, pattern, resetServer, uploadOf } from './support';

let client: GraphLinkClient;

beforeEach(async () => {
  await resetServer();
  client = newClient();
});

describe('a realistic product lifecycle', () => {
  it('create, read, list, update, rename, gallery, delete', async () => {
    const created = await client.mutations.createProduct({ input: { name: 'Lamp', price: 30, tags: ['home'] } });
    expect(created.name).toBe('Lamp');
    expect(created.status).toBe(Status.Active);

    const fetched = (await client.queries.product({ id: created.id }))!;
    expect(fetched.price).toBe(30);

    const byTag = await client.queries.products({ filter: { tag: 'home' } });
    expect(byTag.map((p) => p.id)).toEqual([created.id]);

    const byIds = await client.queries.products({ ids: ['p1', created.id] });
    expect(new Set(byIds.map((p) => p.id))).toEqual(new Set(['p1', created.id]));

    const patched = await client.mutations.patchProduct({ id: created.id, input: { name: 'Lamp 2', price: 35 } });
    expect([patched.name, patched.price]).toEqual(['Lamp 2', 35]);

    const renamed = await client.mutations.renameProduct({ id: created.id, name: 'Lamp 3', note: 'n' });
    expect([renamed.name, renamed.tags]).toEqual(['Lamp 3', ['n']]);

    const gallery = await client.mutations.gallery({
      id: created.id,
      title: 'Gallery é',
      files: [uploadOf(pattern(100), { filename: 'a.png' }), uploadOf(pattern(200), { filename: 'b.png' })],
    });
    expect([gallery.name, gallery.tags]).toEqual(['Gallery é', ['a.png', 'b.png']]);

    const replaced = await client.mutations.replaceProduct({ id: created.id, input: { name: 'Final' } });
    expect(replaced.name).toBe('Final');

    await client.mutations.deleteProduct({ id: created.id });
    const failure = await client.queries.product({ id: created.id }).catch((e: unknown) => e);
    expect(failure).toBeInstanceOf(RestError);
    expect((failure as RestError).status).toBe(404);
  });

  it('Void succeeds on 204 and fails with RestError on a missing resource', async () => {
    await client.mutations.deleteProduct({ id: 'p2' });
    const failure = await client.mutations.deleteProduct({ id: 'p2' }).catch((e: unknown) => e);
    expect(failure).toBeInstanceOf(RestError);
    expect((failure as RestError).status).toBe(404);
  });

  it('the same client serves many concurrent calls correctly', async () => {
    const results = await Promise.all(
      Array.from({ length: 40 }, (_, i) => client.mutations.createProduct({ input: { name: `item-${i}` } })),
    );
    expect(new Set(results.map((p) => p.name)).size).toBe(40);
    expect(new Set(results.map((p) => p.id)).size).toBe(40);
    const listed = await client.queries.products({});
    expect(listed.length).toBe(42);
  });

  it('products list with no filters sends no query', async () => {
    expect((await client.queries.products({})).map((p) => p.id)).toEqual(['p1', 'p2']);
  });
});
