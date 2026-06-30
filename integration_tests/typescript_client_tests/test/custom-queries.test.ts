import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { UserStatus } from '../lib/generated/enums/user-status.js';
import type { UserResult } from '../lib/generated/types/user-result.js';
import type { PostResult } from '../lib/generated/types/post-result.js';
import { MockAdapter, MockWsAdapter } from './mock-adapter.ts';
import { kUserAliceJson, kPostJson } from './fixtures.ts';

let adapter: MockAdapter;
let client: GraphLinkClient;

beforeEach(() => {
  adapter = new MockAdapter();
  client = new GraphLinkClient(adapter.call, new MockWsAdapter());
});

// ── fetchUserAndPost ──────────────────────────────────────────────────────────

describe('fetchUserAndPost', () => {
  beforeEach(() => {
    adapter.registerData('fetchUserAndPost', { user: kUserAliceJson, post: kPostJson });
  });

  it('res.user.name is correct', async () => {
    const res = await client.queries.fetchUserAndPost({ userId: 'user-1', postId: 'post-1' });
    expect(res.user.name).toBe('Alice Smith');
  });

  it('res.user.id is correct', async () => {
    const res = await client.queries.fetchUserAndPost({ userId: 'user-1', postId: 'post-1' });
    expect(res.user.id).toBe('user-1');
  });

  it('res.post.title is correct', async () => {
    const res = await client.queries.fetchUserAndPost({ userId: 'user-1', postId: 'post-1' });
    expect(res.post.title).toBe('Hello World');
  });

  it('res.post.author.id is correct', async () => {
    const res = await client.queries.fetchUserAndPost({ userId: 'user-1', postId: 'post-1' });
    expect(res.post.author.id).toBe('user-1');
  });
});

// ── fetchUserSummary — projected type ─────────────────────────────────────────

describe('fetchUserSummary — projected type', () => {
  beforeEach(() => {
    adapter.registerData('fetchUserSummary', {
      getUser: { id: 'user-1', name: 'Alice Smith', status: 'ACTIVE' },
    });
  });

  it('id is accessible', async () => {
    const res = await client.queries.fetchUserSummary({ id: 'user-1' });
    expect(res.getUser.id).toBe('user-1');
  });

  it('name is accessible', async () => {
    const res = await client.queries.fetchUserSummary({ id: 'user-1' });
    expect(res.getUser.name).toBe('Alice Smith');
  });

  it('status is deserialized as enum', async () => {
    const res = await client.queries.fetchUserSummary({ id: 'user-1' });
    expect(res.getUser.status).toBe(UserStatus.Active);
  });
});

// ── fetchCachedPair — independent caching ────────────────────────────────────

describe('fetchCachedPair — independent caching', () => {
  it('second call with same args hits cache — adapter called once', async () => {
    adapter.registerData('fetchCachedPair', { user: kUserAliceJson, post: kPostJson });
    await client.queries.fetchCachedPair({ userId: 'user-1', postId: 'post-1' });
    await client.queries.fetchCachedPair({ userId: 'user-1', postId: 'post-1' });
    expect(adapter.callCount).toBe(1);
  });

  it('different postId causes a second network call', async () => {
    adapter.registerData('fetchCachedPair', { user: kUserAliceJson, post: kPostJson });
    await client.queries.fetchCachedPair({ userId: 'user-1', postId: 'post-1' });
    await client.queries.fetchCachedPair({ userId: 'user-1', postId: 'post-2' });
    expect(adapter.callCount).toBe(2);
  });

  it('data is correct on cache hit', async () => {
    adapter.registerData('fetchCachedPair', { user: kUserAliceJson, post: kPostJson });
    await client.queries.fetchCachedPair({ userId: 'user-1', postId: 'post-1' });
    const res = await client.queries.fetchCachedPair({ userId: 'user-1', postId: 'post-1' });
    expect(res.user.name).toBe('Alice Smith');
    expect(res.post.title).toBe('Hello World');
  });
});

// ── search — auto-generated query, interface dispatch ────────────────────────

const kSearchPayload = {
  search: [
    { __typename: 'UserResult', id: 'ur-1', name: 'Alice', email: 'alice@test.com' },
    { __typename: 'PostResult', id: 'pr-1', title: 'Hello World' },
  ],
};

describe('search — auto-generated, __typename in response', () => {
  beforeEach(() => { adapter.registerData('search', kSearchPayload); });

  it('search list has two elements', async () => {
    const res = await client.queries.search({ term: 'test' });
    expect(res.search).toHaveLength(2);
  });

  it('first element has UserResult fields', async () => {
    const res = await client.queries.search({ term: 'test' });
    expect('name' in res.search[0]).toBe(true);
    const u = res.search[0] as UserResult;
    expect(u.id).toBe('ur-1');
    expect(u.name).toBe('Alice');
    expect(u.email).toBe('alice@test.com');
  });

  it('second element has PostResult fields', async () => {
    const res = await client.queries.search({ term: 'test' });
    expect('title' in res.search[1]).toBe(true);
    const p = res.search[1] as PostResult;
    expect(p.id).toBe('pr-1');
    expect(p.title).toBe('Hello World');
  });
});

// ── runSearch — custom query, interface dispatch ──────────────────────────────

describe('runSearch — __typename dispatch', () => {
  beforeEach(() => { adapter.registerData('runSearch', kSearchPayload); });

  it('search list has two elements', async () => {
    const res = await client.queries.runSearch({ term: 'test' });
    expect(res.search).toHaveLength(2);
  });

  it('first element has UserResult fields', async () => {
    const res = await client.queries.runSearch({ term: 'test' });
    expect('name' in res.search[0]).toBe(true);
  });

  it('second element has PostResult fields', async () => {
    const res = await client.queries.runSearch({ term: 'test' });
    expect('title' in res.search[1]).toBe(true);
  });

  it('UserResult has correct name', async () => {
    const res = await client.queries.runSearch({ term: 'test' });
    const userResult = res.search[0] as UserResult;
    expect(userResult.name).toBe('Alice');
  });

  it('UserResult has correct email', async () => {
    const res = await client.queries.runSearch({ term: 'test' });
    const userResult = res.search[0] as UserResult;
    expect(userResult.email).toBe('alice@test.com');
  });

  it('PostResult has correct title', async () => {
    const res = await client.queries.runSearch({ term: 'test' });
    const postResult = res.search[1] as PostResult;
    expect(postResult.title).toBe('Hello World');
  });
});
