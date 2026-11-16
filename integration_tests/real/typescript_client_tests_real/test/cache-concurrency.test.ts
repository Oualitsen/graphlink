import { describe, it, expect } from 'vitest';
import { newClient } from './real-server-adapter.ts';

let n = 0;
const freshId = () => `ts-${Date.now()}-${n++}`;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

describe('cached requests at the same time', () => {
  it('concurrent requests for two different keys make two calls', async () => {
    const client = newClient();
    const id = freshId();
    await Promise.all([
      client.queries.cachedSlow({ id: `${id}-a`, delayMs: 300 }),
      client.queries.cachedSlow({ id: `${id}-b`, delayMs: 300 }),
    ]);
    expect((await client.queries.cachedSlowCalls({ id: `${id}-a` })).cachedSlowCalls).toBe(1);
    expect((await client.queries.cachedSlowCalls({ id: `${id}-b` })).cachedSlowCalls).toBe(1);
  });

  it('a response that was in flight during an invalidation is not stored', async () => {
    const client = newClient();
    const id = freshId();
    const slow = client.queries.cachedSlow({ id, delayMs: 600 });
    await sleep(150);
    await client.mutations.bumpSlow({ id });
    expect((await slow).cachedSlow).toBe(0);
    expect((await client.queries.cachedSlow({ id, delayMs: 600 })).cachedSlow).toBe(1);
  });
});
