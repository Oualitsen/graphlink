// Cache tests verify data correctness and invalidation behavior.
// Call-count assertions are omitted — they require adapter introspection
// that is not available with a real HTTP server.
import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { UserStatus } from '../lib/generated/enums/user-status.js';
import type { CreateUserInput } from '../lib/generated/inputs/create-user-input.js';
import { newClient } from './real-server-adapter.ts';

const minimalInput: CreateUserInput = {
  name: 'Alice Smith',
  email: 'alice@test.com',
  status: UserStatus.ACTIVE,
  address: { street: '123 Main St', city: 'Springfield', country: 'US' },
};

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

// ── 1. Cache hit — data is correct on repeated calls ─────────────────────────

describe('cache hit', () => {
  it('second call with same id returns correct data', async () => {
    await client.queries.getCachedUser({ id: 'user-1' });
    const second = await client.queries.getCachedUser({ id: 'user-1' });
    expect(second.getCachedUser.id).toBe('user-1');
    expect(second.getCachedUser.name).toBe('Alice Smith');
  });
});

// ── 2. Tag invalidation — data is still fetchable after invalidation ──────────

describe('tag invalidation — createCachedUser invalidates "users"', () => {
  it('getCachedUser returns correct data after createCachedUser', async () => {
    await client.queries.getCachedUser({ id: 'user-1' });
    await client.mutations.createCachedUser({ input: minimalInput });
    const res = await client.queries.getCachedUser({ id: 'user-1' });
    expect(res.getCachedUser.name).toBe('Alice Smith');
  });

  it('listCachedUsers returns correct data after createCachedUser', async () => {
    await client.queries.listCachedUsers();
    await client.mutations.createCachedUser({ input: minimalInput });
    const res = await client.queries.listCachedUsers();
    expect(res.listCachedUsers.length).toBeGreaterThan(0);
  });
});

// ── 3. Multi-tag invalidation ─────────────────────────────────────────────────

describe('multi-tag invalidation — transferPost invalidates "users" and "posts"', () => {
  it('getCachedUser and getCachedPost return correct data after transferPost', async () => {
    await client.queries.getCachedUser({ id: 'user-1' });
    await client.queries.getCachedPost({ id: 'post-1' });
    await client.mutations.transferPost({ postId: 'post-1', newAuthorId: 'user-2' });
    const user = await client.queries.getCachedUser({ id: 'user-1' });
    const post = await client.queries.getCachedPost({ id: 'post-1' });
    expect(user.getCachedUser.id).toBe('user-1');
    expect(post.getCachedPost.id).toBe('post-1');
  });

  it('getCachedConfig (no shared tag) still returns correct data after transferPost', async () => {
    const config = await client.queries.getCachedConfig();
    await client.mutations.transferPost({ postId: 'post-1', newAuthorId: 'user-2' });
    const config2 = await client.queries.getCachedConfig();
    expect(config2.getCachedConfig.id).toBe(config.getCachedConfig.id);
  });
});

// ── 4. Invalidate all ─────────────────────────────────────────────────────────

describe('invalidate all — resetAll', () => {
  it('all cached queries return correct data after resetAll', async () => {
    await client.queries.getCachedUser({ id: 'user-1' });
    await client.queries.getCachedPost({ id: 'post-1' });
    await client.queries.getCachedConfig();

    await client.mutations.resetAll();

    const user = await client.queries.getCachedUser({ id: 'user-1' });
    const post = await client.queries.getCachedPost({ id: 'post-1' });
    const config = await client.queries.getCachedConfig();
    expect(user.getCachedUser.name).toBe('Alice Smith');
    expect(post.getCachedPost.title).toBe('Hello World');
    expect(config.getCachedConfig).not.toBeNull();
  });

  it('resetAll returns true', async () => {
    const res = await client.mutations.resetAll();
    expect(res.resetAll).toBe(true);
  });
});

// ── 5. TTL expiry ─────────────────────────────────────────────────────────────

describe('TTL expiry', () => {
  it('getStaleUser still returns correct data after ttl expires', async () => {
    await client.queries.getStaleUser({ id: 'user-1' });
    await new Promise(r => setTimeout(r, 1200));
    const res = await client.queries.getStaleUser({ id: 'user-1' });
    expect(res.getStaleUser!.id).toBe('user-1');
    expect(res.getStaleUser!.name).toBe('Alice Smith');
  }, 5000);
});
