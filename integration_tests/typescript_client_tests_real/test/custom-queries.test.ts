import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { UserStatus } from '../lib/generated/enums/user-status.js';
import type { UserResult } from '../lib/generated/types/user-result.js';
import type { PostResult } from '../lib/generated/types/post-result.js';
import { newClient } from './real-server-adapter.ts';

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

// ── fetchUserAndPost ──────────────────────────────────────────────────────────

describe('fetchUserAndPost', () => {
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
    expect(res.getUser.status).toBe(UserStatus.ACTIVE);
  });
});

// ── fetchCachedPair — data correctness ────────────────────────────────────────

describe('fetchCachedPair — data correctness', () => {
  it('user and post data is correct', async () => {
    const res = await client.queries.fetchCachedPair({ userId: 'user-1', postId: 'post-1' });
    expect(res.user.name).toBe('Alice Smith');
    expect(res.post.title).toBe('Hello World');
  });

  it('second call with same args returns correct data', async () => {
    await client.queries.fetchCachedPair({ userId: 'user-1', postId: 'post-1' });
    const res = await client.queries.fetchCachedPair({ userId: 'user-1', postId: 'post-1' });
    expect(res.user.name).toBe('Alice Smith');
    expect(res.post.title).toBe('Hello World');
  });
});

// ── runSearch — custom query, union dispatch ──────────────────────────────────
// Note: the auto-generated search query uses a fragment structure that Spring
// rejects; use runSearch (custom operation) for union dispatch testing.

describe('runSearch — __typename dispatch', () => {
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
    expect(userResult.name).toBe('Alice Smith');
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
