import { beforeEach, describe, expect, it } from 'vitest';
import { Cat, Dog, RestError, Status, type GraphLinkClient } from '../lib/generated/graphlink';
import { newClient, resetServer } from './support';

let client: GraphLinkClient;

beforeEach(async () => {
  await resetServer();
  client = newClient();
});

describe('status handling', () => {
  it('200 and 201 decode the body', async () => {
    expect((await client.queries.status({ code: 200 }))!.name).toBe('Pen');
    expect((await client.queries.status({ code: 201 }))!.id).toBe('p1');
  });

  it('204 is null for a nullable result and a decode error for a non-null one', async () => {
    expect(await client.queries.status({ code: 204 })).toBeNull();
    await expect(client.queries.statusNonNull({ code: 204 })).rejects.toThrow(/Empty REST response/);
  });

  for (const code of [400, 401, 403, 404, 409, 422, 500, 502, 503]) {
    it(`${code} raises RestError with status, headers and body`, async () => {
      const failure = await client.queries.status({ code }).catch((e: unknown) => e);
      expect(failure).toBeInstanceOf(RestError);
      const error = failure as RestError;
      expect(error.status).toBe(code);
      expect(error.body).toContain(`status ${code}`);
      expect(error.headers['x-reason']).toBe(`reason-${code}`);
    });
  }

  it('an error status is never turned into null, even for a nullable result', async () => {
    await expect(client.queries.status({ code: 404 })).rejects.toBeInstanceOf(RestError);
  });

  it('a RestError is catchable by type and prints its status', async () => {
    try {
      await client.queries.status({ code: 418 });
      expect.unreachable('should throw');
    } catch (e) {
      expect(e).toBeInstanceOf(RestError);
      expect(String(e)).toContain('418');
    }
  });

  it('a failed call does not poison the connection for the next one', async () => {
    await expect(client.queries.status({ code: 500 })).rejects.toBeInstanceOf(RestError);
    expect((await client.queries.status({ code: 200 }))!.id).toBe('p1');
  });
});

describe('empty bodies', () => {
  it('an empty 200 is null when nullable and an error when not', async () => {
    expect(await client.queries.blank()).toBeNull();
    await expect(client.queries.blankNonNull()).rejects.toThrow(/Empty REST response/);
  });

  it('204 is null when nullable', async () => {
    expect(await client.queries.noContent()).toBeNull();
    expect(await client.queries.textOptional()).toBeNull();
  });

  it('a JSON null literal is null when nullable', async () => {
    expect(await client.queries.jsonNull()).toBeNull();
  });
});

describe('value kinds', () => {
  it('scalars', async () => {
    expect(await client.queries.count()).toBe(7);
    expect(await client.queries.flag()).toBe(true);
  });

  it('TEXT is returned verbatim, decoded as UTF-8', async () => {
    expect(await client.queries.text()).toBe('héllo ✓');
  });

  it('responsePath selects a nested value', async () => {
    expect(await client.queries.deep()).toEqual([1, 2, 3]);
    const items = await client.queries.wrapped();
    expect(items.map((p) => p.id)).toEqual(['p1', 'p2']);
  });

  it('non-ASCII JSON text decodes correctly', async () => {
    const p = await client.queries.unicode();
    expect(p.name).toBe('é漢😀 "quoted"');
    expect(p.tags).toEqual(['ß']);
  });

  it('unknown JSON keys are ignored and a null list stays null', async () => {
    const p = await client.queries.extraKeys();
    expect(p.id).toBe('x');
    expect(p.tags).toBeNull();
  });

  it('a missing non-null field is a decode error naming the type and field', async () => {
    await expect(client.queries.missingField()).rejects.toThrow('Product.name is missing or null in the response');
  });

  it('nested types, enums and cyclic references decode', async () => {
    const p = (await client.queries.product({ id: 'p1' }))!;
    expect(p.status).toBe(Status.Active);
    expect(p.related!.length).toBe(1);
    expect(p.related![0].name).toBe('Book');
    expect(p.related![0].related).toBeNull();
  });
});

describe('polymorphism', () => {
  it('an interface decodes through the discriminator field', async () => {
    const pets = await client.queries.pets();
    expect(pets[0].__typename).toBe('Dog');
    expect((pets[0] as Dog).barks).toBe(true);
    expect(pets[1].__typename).toBe('Cat');
    expect((pets[1] as Cat).lives).toBe(9);
  });

  it('a single interface value', async () => {
    const pet = await client.queries.pet({ id: 'c1' });
    expect(pet!.__typename).toBe('Cat');
    expect(pet!.name).toBe('Tom');
  });

  it('an unknown discriminator value is an error naming the parent and the value', async () => {
    await expect(client.queries.petsUnknown()).rejects.toThrow(/Pet.*bird/);
  });

  it('a union decodes through its discriminator values map', async () => {
    const hits = await client.queries.hits();
    expect(hits[0].__typename).toBe('Product');
    expect(hits[1].__typename).toBe('Owner');
  });
});

describe('GraphQL and REST on one client', () => {
  it('a GraphQL query and REST operations are served by the same client', async () => {
    expect((await client.queries.getCount()).getCount).toBe(19);
    expect(await client.queries.count()).toBe(7);
    expect((await client.queries.getCount()).getCount).toBe(19);
  });
});
