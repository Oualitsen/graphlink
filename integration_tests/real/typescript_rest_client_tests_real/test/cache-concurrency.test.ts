import { beforeEach, describe, expect, it } from 'vitest';
import { InMemoryGraphLinkCacheStore, type GraphLinkCacheStore, type GraphLinkClient } from '../lib/generated/graphlink';
import { newClient, resetServer } from './support';

const delay = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

let client: GraphLinkClient;
let name: string;
let sequence = 0;

beforeEach(async () => {
  await resetServer();
  name = `ts-${Date.now()}-${sequence++}`;
  client = newClient({ store: new InMemoryGraphLinkCacheStore() });
});

describe('cached REST calls under concurrency', () => {
  it('concurrent requests for two different keys make two calls', async () => {
    await Promise.all([
      client.queries.counterSlow({ name: `${name}-a`, delayMs: 300 }),
      client.queries.counterSlow({ name: `${name}-b`, delayMs: 300 }),
    ]);
    expect((await client.queries.counterCalls({ name: `${name}-a` })).n).toBe(1);
    expect((await client.queries.counterCalls({ name: `${name}-b` })).n).toBe(1);
  });

  it('concurrent requests for the same key share one call', async () => {
    const results = await Promise.all([
      client.queries.counterSlow({ name, delayMs: 300 }),
      client.queries.counterSlow({ name, delayMs: 300 }),
      client.queries.counterSlow({ name, delayMs: 300 }),
    ]);
    expect(results.map((r) => r.n)).toEqual([1, 1, 1]);
    expect((await client.queries.counterCalls({ name })).n).toBe(1);
  });

  it('a response that was in flight during an invalidation is not stored', async () => {
    const slow = client.queries.counterSlow({ name, delayMs: 600 });
    await delay(150);
    await client.mutations.touchSlow({ name });
    expect((await slow).n).toBe(1);
    expect((await client.queries.counterSlow({ name, delayMs: 600 })).n).toBe(2);
  });

  it('an invalidation that arrives while the response is being stored removes it', async () => {
    let reached!: () => void;
    const reachedPromise = new Promise<void>((resolve) => { reached = resolve; });
    let release!: () => void;
    const releasePromise = new Promise<void>((resolve) => { release = resolve; });
    let paused = false;
    const inner = new InMemoryGraphLinkCacheStore();
    const store: GraphLinkCacheStore = {
      get: (key) => inner.get(key),
      invalidate: (key) => inner.invalidate(key),
      invalidateAll: () => inner.invalidateAll(),
      set: async (key, value) => {
        if (!key.startsWith('__tag__') && !paused) {
          paused = true;
          reached();
          await releasePromise;
        }
        await inner.set(key, value);
      },
    };
    const pausing = newClient({ store });
    const first = pausing.queries.counterSlow({ name, delayMs: 50 });
    await reachedPromise;
    const touch = pausing.mutations.touchSlow({ name });
    await delay(300);
    release();
    await Promise.all([first, touch]);
    expect((await pausing.queries.counterSlow({ name, delayMs: 50 })).n).toBe(2);
  });
});
