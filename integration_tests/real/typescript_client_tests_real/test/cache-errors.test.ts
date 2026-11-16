import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { newClient } from './real-server-adapter.ts';

// The server fails the first cachedFlaky / cachedFlakyNullable call per id and counts every call.
let client: GraphLinkClient;
let id: string;
let next = 0;
beforeEach(() => {
  client = newClient();
  id = `ts-${Date.now()}-${next++}`;
});

const serverCalls = async () => (await client.queries.cachedFlakyCalls({ id })).cachedFlakyCalls;

describe('a failed response is not cached', () => {
  it('the success after the failure is fetched, then served from the cache', async () => {
    await expect(client.queries.cachedFlaky({ id })).rejects.toBeDefined();
    expect(await serverCalls()).toBe(1);

    expect((await client.queries.cachedFlaky({ id })).cachedFlaky.id).toBe('user-1');
    expect(await serverCalls()).toBe(2);

    expect((await client.queries.cachedFlaky({ id })).cachedFlaky.id).toBe('user-1');
    expect(await serverCalls()).toBe(2);
  });

  it('a partial failure (200, null field, errors) is not cached either', async () => {
    await expect(client.queries.cachedFlakyNullable({ id })).rejects.toBeDefined();
    expect(await serverCalls()).toBe(1);

    expect((await client.queries.cachedFlakyNullable({ id })).cachedFlakyNullable?.id).toBe('user-1');
    expect(await serverCalls()).toBe(2);

    expect((await client.queries.cachedFlakyNullable({ id })).cachedFlakyNullable?.id).toBe('user-1');
    expect(await serverCalls()).toBe(2);
  });
});
