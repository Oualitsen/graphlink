import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { UserStatus } from '../lib/generated/enums/user-status.js';
import type { CreateUserInput } from '../lib/generated/inputs/create-user-input.js';
import { MockAdapter, MockWsAdapter } from './mock-adapter.ts';
import { kUserAliceJson, kPostJson, kAllScalarsNullJson } from './fixtures.ts';

const minimalInput: CreateUserInput = {
  name: 'Alice Smith',
  email: 'alice@test.com',
  status: UserStatus.ACTIVE,
  address: { street: '123 Main St', city: 'Springfield', country: 'US' },
};

// Fresh client per test — each test starts with an empty in-memory cache.
let adapter: MockAdapter;
let client: GraphLinkClient;

beforeEach(() => {
  adapter = new MockAdapter();
  client = new GraphLinkClient(adapter.call, new MockWsAdapter());
});

// ── 1. Cache hit ──────────────────────────────────────────────────────────────

describe('cache hit', () => {
  it('getCachedUser called twice with same id — adapter called once', async () => {
    adapter.registerData('getCachedUser', { getCachedUser: kUserAliceJson });
    await client.queries.getCachedUser({ id: 'user-1' });
    await client.queries.getCachedUser({ id: 'user-1' });
    expect(adapter.callCount).toBe(1);
  });

  it('second call returns same data as first', async () => {
    adapter.registerData('getCachedUser', { getCachedUser: kUserAliceJson });
    const first = await client.queries.getCachedUser({ id: 'user-1' });
    const second = await client.queries.getCachedUser({ id: 'user-1' });
    expect(second.getCachedUser.id).toBe(first.getCachedUser.id);
    expect(second.getCachedUser.name).toBe('Alice Smith');
  });
});

// ── 2. Different args — each key is cached independently ──────────────────────

describe('cache miss on different args', () => {
  it('getCachedUser with two different ids — adapter called twice', async () => {
    adapter.registerData('getCachedUser', { getCachedUser: kUserAliceJson });
    await client.queries.getCachedUser({ id: 'user-1' });
    await client.queries.getCachedUser({ id: 'user-2' });
    expect(adapter.callCount).toBe(2);
  });

  it('third call with first id is still a hit — adapter not called again', async () => {
    adapter.registerData('getCachedUser', { getCachedUser: kUserAliceJson });
    await client.queries.getCachedUser({ id: 'user-1' });
    await client.queries.getCachedUser({ id: 'user-2' });
    await client.queries.getCachedUser({ id: 'user-1' });
    expect(adapter.callCount).toBe(2);
  });
});

// ── 3. Tag invalidation ───────────────────────────────────────────────────────

describe('tag invalidation — createCachedUser invalidates "users"', () => {
  it('getCachedUser misses after createCachedUser', async () => {
    adapter.registerData('getCachedUser', { getCachedUser: kUserAliceJson });
    adapter.registerData('createCachedUser', { createCachedUser: kUserAliceJson });

    await client.queries.getCachedUser({ id: 'user-1' });   // count: 1
    await client.queries.getCachedUser({ id: 'user-1' });   // hit
    expect(adapter.callCount).toBe(1);

    await client.mutations.createCachedUser({ input: minimalInput }); // count: 2

    await client.queries.getCachedUser({ id: 'user-1' });   // count: 3 — miss
    expect(adapter.callCount).toBe(3);
  });

  it('listCachedUsers also invalidated by createCachedUser (same tag)', async () => {
    adapter.registerData('listCachedUsers', { listCachedUsers: [kUserAliceJson] });
    adapter.registerData('createCachedUser', { createCachedUser: kUserAliceJson });

    await client.queries.listCachedUsers();   // count: 1
    await client.queries.listCachedUsers();   // hit

    await client.mutations.createCachedUser({ input: minimalInput }); // count: 2

    await client.queries.listCachedUsers();   // count: 3 — miss
    expect(adapter.callCount).toBe(3);
  });
});

// ── 4. Multi-tag invalidation ─────────────────────────────────────────────────

describe('multi-tag invalidation — transferPost invalidates "users" and "posts"', () => {
  it('getCachedUser and getCachedPost both miss after transferPost', async () => {
    adapter.registerData('getCachedUser', { getCachedUser: kUserAliceJson });
    adapter.registerData('getCachedPost', { getCachedPost: kPostJson });
    adapter.registerData('transferPost', { transferPost: kPostJson });

    await client.queries.getCachedUser({ id: 'user-1' }); // count: 1
    await client.queries.getCachedPost({ id: 'post-1' }); // count: 2

    await client.queries.getCachedUser({ id: 'user-1' }); // hit
    await client.queries.getCachedPost({ id: 'post-1' }); // hit
    expect(adapter.callCount).toBe(2);

    await client.mutations.transferPost({ postId: 'post-1', newAuthorId: 'user-2' }); // count: 3

    await client.queries.getCachedUser({ id: 'user-1' }); // count: 4 — miss
    await client.queries.getCachedPost({ id: 'post-1' }); // count: 5 — miss
    expect(adapter.callCount).toBe(5);
  });

  it('getCachedConfig (no shared tag) is NOT invalidated by transferPost', async () => {
    adapter.registerData('getCachedConfig', { getCachedConfig: kAllScalarsNullJson });
    adapter.registerData('transferPost', { transferPost: kPostJson });

    await client.queries.getCachedConfig();                                          // count: 1
    await client.mutations.transferPost({ postId: 'post-1', newAuthorId: 'user-2' }); // count: 2
    await client.queries.getCachedConfig();                                          // still cached

    expect(adapter.callCount).toBe(2);
  });
});

// ── 5. Invalidate all ─────────────────────────────────────────────────────────

describe('invalidate all — resetAll wipes the entire cache', () => {
  it('all cached queries miss after resetAll', async () => {
    adapter.registerData('getCachedUser', { getCachedUser: kUserAliceJson });
    adapter.registerData('getCachedPost', { getCachedPost: kPostJson });
    adapter.registerData('getCachedConfig', { getCachedConfig: kAllScalarsNullJson });
    adapter.registerData('resetAll', { resetAll: true });

    await client.queries.getCachedUser({ id: 'user-1' });  // count: 1
    await client.queries.getCachedPost({ id: 'post-1' });  // count: 2
    await client.queries.getCachedConfig();                  // count: 3

    await client.mutations.resetAll();                       // count: 4

    await client.queries.getCachedUser({ id: 'user-1' });  // count: 5 — miss
    await client.queries.getCachedPost({ id: 'post-1' });  // count: 6 — miss
    await client.queries.getCachedConfig();                  // count: 7 — miss
    expect(adapter.callCount).toBe(7);
  });

  it('resetAll returns true', async () => {
    adapter.registerData('resetAll', { resetAll: true });
    const res = await client.mutations.resetAll();
    expect(res.resetAll).toBe(true);
  });
});

// ── 6. TTL expiry ─────────────────────────────────────────────────────────────

describe('TTL expiry', () => {
  it('getStaleUser re-fetches after ttl expires', async () => {
    adapter.registerData('getStaleUser', { getStaleUser: kUserAliceJson });

    await client.queries.getStaleUser({ id: 'user-1' }); // ttl: 1s
    expect(adapter.callCount).toBe(1);

    await new Promise(r => setTimeout(r, 1200));

    await client.queries.getStaleUser({ id: 'user-1' }); // expired
    expect(adapter.callCount).toBe(2);
  }, 5000);
});

// ── 7. staleIfOffline ─────────────────────────────────────────────────────────

describe('staleIfOffline', () => {
  it('returns stale value when network fails after TTL expires', async () => {
    adapter.registerData('getStaleUser', { getStaleUser: kUserAliceJson });

    await client.queries.getStaleUser({ id: 'user-1' }); // warms cache
    expect(adapter.callCount).toBe(1);

    await new Promise(r => setTimeout(r, 1200)); // TTL expires

    adapter.simulateFailure = true;

    const res = await client.queries.getStaleUser({ id: 'user-1' });
    expect(res.getStaleUser).not.toBeNull();
    expect(res.getStaleUser!.name).toBe('Alice Smith');
    expect(adapter.callCount).toBe(1); // no new call recorded (threw before recording)
  }, 5000);

  it('throws when network fails and no stale value exists', async () => {
    adapter.simulateFailure = true;
    await expect(client.queries.getStaleUser({ id: 'user-1' })).rejects.toThrow();
  });
});

// ── 8. No cache ───────────────────────────────────────────────────────────────

describe('no cache', () => {
  it('getUser (no @glCache) — adapter called on every request', async () => {
    adapter.registerData('getUser', { getUser: kUserAliceJson });
    await client.queries.getUser({ id: 'user-1' });
    await client.queries.getUser({ id: 'user-1' });
    expect(adapter.callCount).toBe(2);
  });
});
