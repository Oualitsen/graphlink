import { describe, expect, it } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client';
import { createFetchAdapter } from '../lib/generated/client/graph-link-adapters';
import { createRestFetchAdapter } from '../lib/generated/client/graph-link-rest-adapters';
import { RestError } from '../lib/generated/client/graph-link-rest';
import { GraphLinkDomainError } from '../lib/generated/client/graph-link-domain-error';
import { ItemConflict } from '../lib/generated/errors/item-conflict';
import { ItemNotFound } from '../lib/generated/errors/item-not-found';
import { RateLimited } from '../lib/generated/errors/rate-limited';
import { Teapot } from '../lib/generated/errors/teapot';

const client = new GraphLinkClient(createFetchAdapter('http://127.0.0.1:9930/graphql'), createRestFetchAdapter('http://127.0.0.1:9930'));

async function thrownBy(call: () => Promise<unknown>): Promise<unknown> {
  try {
    await call();
  } catch (e) {
    return e;
  }
  throw new Error('expected an exception');
}

describe('rest errors', () => {
  it('a successful call returns its data', async () => {
    expect((await client.queries.item({ id: '1' })).name).toBe('Item 1');
  });

  it('a status-only error is thrown with the fields of the body', async () => {
    const e = await thrownBy(() => client.queries.item({ id: 'missing' }));
    expect(e).toBeInstanceOf(ItemNotFound);
    expect(e).toBeInstanceOf(GraphLinkDomainError);
    expect((e as ItemNotFound).id).toBe('missing');
    expect((e as ItemNotFound).message).toBe('Item missing not found');
  });

  it('it can be caught by type', async () => {
    let caught = '';
    try {
      await client.queries.item({ id: 'conflict' });
    } catch (e) {
      if (e instanceof ItemConflict) caught = e.reason;
    }
    expect(caught).toBe('duplicate');
  });

  it('a status with its own value matches the body code', async () => {
    const e = await thrownBy(() => client.queries.item({ id: 'conflict' }));
    expect(e).toBeInstanceOf(ItemConflict);
    expect((e as ItemConflict).message).toBe('Conflict');
  });

  it('a custom field path is read from the body', async () => {
    const e = await thrownBy(() => client.queries.item({ id: 'rate' }));
    expect(e).toBeInstanceOf(RateLimited);
    expect((e as RateLimited).retryAfter).toBe(30);
  });

  it('a status-only error does not need a JSON body', async () => {
    expect(await thrownBy(() => client.queries.item({ id: 'teapot' }))).toBeInstanceOf(Teapot);
  });

  it('a status-only error with an HTML body still matches by status', async () => {
    const e = await thrownBy(() => client.queries.item({ id: 'html-404' }));
    expect(e).toBeInstanceOf(ItemNotFound);
    expect((e as ItemNotFound).id).toBeFalsy();
  });

  it('a mutation throws its declared error', async () => {
    const e = await thrownBy(() => client.mutations.createItem({ input: { name: 'dup' } }));
    expect(e).toBeInstanceOf(ItemConflict);
    expect((e as ItemConflict).reason).toBe('name taken');
  });

  it('a mutation returns its data', async () => {
    expect((await client.mutations.createItem({ input: { name: 'fresh' } })).id).toBe('new');
  });

  for (const [name, id, status] of [
    ['a body missing a required field', 'conflict-no-reason', 409],
    ['a code the client does not know', 'conflict-other', 409],
    ['a proxy error with an HTML body', 'bad-gateway', 502],
  ] as const) {
    it(`falls back to RestError: ${name}`, async () => {
      const e = await thrownBy(() => client.queries.item({ id }));
      expect(e).toBeInstanceOf(RestError);
      expect(e).not.toBeInstanceOf(GraphLinkDomainError);
      expect((e as RestError).status).toBe(status);
    });
  }

  it('an operation without @glThrows keeps RestError', async () => {
    const e = await thrownBy(() => client.queries.itemPlain({ id: 'x' }));
    expect(e).toBeInstanceOf(RestError);
    expect((e as RestError).status).toBe(404);
  });
});
