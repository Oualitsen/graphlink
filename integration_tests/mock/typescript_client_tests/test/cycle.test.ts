import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { MockAdapter, MockWsAdapter } from './mock-adapter.ts';
import { kUserAliceJson, kUserWithPostsJson, kPostWithAuthorCycleJson } from './fixtures.ts';

let adapter: MockAdapter;
let client: GraphLinkClient;

beforeEach(() => {
  adapter = new MockAdapter();
  client = new GraphLinkClient(adapter.call, new MockWsAdapter());
});

// The schema has User.posts: [Post!] and Post.author: User! — a cycle.
// The generator breaks it by expanding author's fields inline inside
// _all_fields_Post rather than recursing back to ..._all_fields_User.

describe('User.posts — cycle User → Post → User', () => {
  beforeEach(() => {
    adapter.registerData('getUser', { getUser: kUserWithPostsJson });
  });

  it('User.posts is deserialized as an array', async () => {
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.posts).not.toBeNull();
    expect(Array.isArray(res.getUser.posts)).toBe(true);
  });

  it('User.posts list has the correct length', async () => {
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.posts!.length).toBe(1);
  });

  it('User.posts[0] has correct scalar fields', async () => {
    const res = await client.queries.getUser({ id: 'user-1' });
    const post = res.getUser.posts![0];
    expect(post.id).toBe('post-10');
    expect(post.title).toBe('Cyclic Post');
    expect(post.viewCount).toBe(7);
  });

  it('User.posts[0].author is deserialized (cycle broken at one level)', async () => {
    const res = await client.queries.getUser({ id: 'user-1' });
    const author = res.getUser.posts![0].author;
    expect(author.id).toBe('user-1');
    expect(author.name).toBe('Alice Smith');
  });

  it('User.posts[0].author.address is accessible', async () => {
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.posts![0].author.address.city).toBe('Springfield');
  });

  it('User.posts is null when server returns null', async () => {
    adapter.registerData('getUser', { getUser: kUserAliceJson });
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.posts).toBeNull();
  });
});

describe('Post.author — cycle Post → User → Post', () => {
  beforeEach(() => {
    adapter.registerData('getPost', { getPost: kPostWithAuthorCycleJson });
  });

  it('Post.author is a full User', async () => {
    const res = await client.queries.getPost({ id: 'post-10' });
    expect(res.getPost.author.id).toBe('user-1');
    expect(res.getPost.author.name).toBe('Alice Smith');
  });

  it('Post.author projected type has scalar fields accessible', async () => {
    const res = await client.queries.getPost({ id: 'post-10' });
    expect(res.getPost.author.email).toBe('alice@test.com');
    expect(res.getPost.author.tags).toEqual(['admin']);
  });
});

describe('listUsers with cyclic User.posts', () => {
  it('list of users with posts deserializes correctly', async () => {
    adapter.registerData('listUsers', { listUsers: [kUserWithPostsJson] });
    const res = await client.queries.listUsers();
    expect(res.listUsers.length).toBe(1);
    expect(res.listUsers[0].posts![0].title).toBe('Cyclic Post');
  });
});
