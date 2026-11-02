import { beforeEach, describe, expect, it } from 'vitest';
import { InMemoryGraphLinkCacheStore, RestError, type GraphLinkClient } from '../lib/generated/graphlink';
import { newClient, resetServer } from './support';

let client: GraphLinkClient;
let store: InMemoryGraphLinkCacheStore;

const delay = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

class CountingStore extends InMemoryGraphLinkCacheStore {
  sets = 0;

  override async set(key: string, value: string): Promise<void> {
    this.sets++;
    return super.set(key, value);
  }
}

beforeEach(async () => {
  await resetServer();
  store = new InMemoryGraphLinkCacheStore();
  client = newClient({ store });
});

describe('@glCache on REST queries', () => {
  it('the second call is served from the cache, with no request', async () => {
    const first = await client.queries.counter({ name: 'a' });
    const second = await client.queries.counter({ name: 'a' });
    expect([first.n, second.n]).toEqual([1, 1]);
    expect((await client.queries.counterUncached({ name: 'a' })).n).toBe(2);
  });

  it('different arguments are different entries', async () => {
    expect((await client.queries.counter({ name: 'a' })).n).toBe(1);
    expect((await client.queries.counter({ name: 'b' })).n).toBe(1);
    expect((await client.queries.counter({ name: 'a' })).n).toBe(1);
  });

  it('an operation without @glCache is never cached; @glNoCache neither', async () => {
    expect((await client.queries.counterUncached({ name: 'u' })).n).toBe(1);
    expect((await client.queries.counterUncached({ name: 'u' })).n).toBe(2);
    expect((await client.queries.counterNoCache({ name: 'u' })).n).toBe(3);
    expect((await client.queries.counterNoCache({ name: 'u' })).n).toBe(4);
  });

  it('an entry expires after its ttl', async () => {
    expect((await client.queries.counterShort({ name: 's' })).n).toBe(1);
    expect((await client.queries.counterShort({ name: 's' })).n).toBe(1);
    await delay(1300);
    expect((await client.queries.counterShort({ name: 's' })).n).toBe(2);
  });

  it('the cache is shared by every client using the same store', async () => {
    await client.queries.counter({ name: 'shared' });
    const other = newClient({ store });
    expect((await other.queries.counter({ name: 'shared' })).n).toBe(1);
  });

  it('separate stores do not share entries', async () => {
    await client.queries.counter({ name: 'iso' });
    expect((await newClient().queries.counter({ name: 'iso' })).n).toBe(2);
  });
});

describe('@glCacheInvalidate on REST mutations', () => {
  it('invalidates the entries holding the tag, after a 2xx response', async () => {
    expect((await client.queries.counter({ name: 'c' })).n).toBe(1);
    await client.mutations.bump({ name: 'c' });
    expect((await client.queries.counter({ name: 'c' })).n).toBe(102);
  });

  it('leaves entries with other tags alone', async () => {
    expect((await client.queries.counterOther({ name: 'o' })).n).toBe(1);
    expect((await client.queries.counter({ name: 'o' })).n).toBe(2);
    await client.mutations.bump({ name: 'o' });
    expect((await client.queries.counterOther({ name: 'o' })).n).toBe(1);
    expect((await client.queries.counter({ name: 'o' })).n).toBeGreaterThan(100);
  });

  it('all: true clears everything', async () => {
    await client.queries.counter({ name: 'x' });
    await client.queries.counterOther({ name: 'x' });
    await client.mutations.resetAll({ name: 'x' });
    expect((await client.queries.counter({ name: 'x' })).n).toBe(1);
    expect((await client.queries.counterOther({ name: 'x' })).n).toBe(2);
  });

  it('a failed mutation does not invalidate', async () => {
    await client.queries.counter({ name: 'f' });
    await expect(client.mutations.bumpFails({ code: 500 })).rejects.toBeInstanceOf(RestError);
    expect((await client.queries.counter({ name: 'f' })).n).toBe(1);
  });

  it('a 204 mutation still invalidates', async () => {
    await client.queries.counter({ name: 'g' });
    await client.mutations.bumpFails({ code: 204 });
    expect((await client.queries.counter({ name: 'g' })).n).toBe(2);
  });
});

describe('failures', () => {
  it('an error response is not cached', async () => {
    const writes = new CountingStore();
    const c = newClient({ store: writes });
    await expect(c.queries.cachedStatus({ code: 500 })).rejects.toBeInstanceOf(RestError);
    expect(writes.sets).toBe(0);
    expect((await c.queries.cachedStatus({ code: 200 }))!.id).toBe('p1');
    expect(writes.sets).toBe(1);
  });

  it('a response that fails to decode is not cached', async () => {
    const writes = new CountingStore();
    const c = newClient({ store: writes });
    await expect(c.queries.cachedBad()).rejects.toBeDefined();
    await expect(c.queries.cachedBad()).rejects.toBeDefined();
    expect(writes.sets).toBe(0);
  });

  it('staleIfOffline serves the expired entry on a transport failure only', async () => {
    await client.queries.counterOffline({ name: 'off' });
    await delay(1300);
    const offline = newClient({ baseUrl: 'http://127.0.0.1:1', store });
    expect((await offline.queries.counterOffline({ name: 'off' })).n).toBe(1);
  });

  it('without staleIfOffline a transport failure surfaces', async () => {
    await client.queries.counterShort({ name: 'off2' });
    await delay(1300);
    const offline = newClient({ baseUrl: 'http://127.0.0.1:1', store });
    const failure = await offline.queries.counterShort({ name: 'off2' }).catch((e: unknown) => e);
    expect(failure).toBeInstanceOf(Error);
    expect(failure).not.toBeInstanceOf(RestError);
  });

  it('a fresh entry is served even when the server is unreachable', async () => {
    await client.queries.counter({ name: 'fresh' });
    const offline = newClient({ baseUrl: 'http://127.0.0.1:1', store });
    expect((await offline.queries.counter({ name: 'fresh' })).n).toBe(1);
  });

  it('nothing cached and the server unreachable is a transport error', async () => {
    const offline = newClient({ baseUrl: 'http://127.0.0.1:1', store });
    const failure = await offline.queries.counter({ name: 'never' }).catch((e: unknown) => e);
    expect(failure).toBeInstanceOf(Error);
    expect(failure).not.toBeInstanceOf(RestError);
  });
});
