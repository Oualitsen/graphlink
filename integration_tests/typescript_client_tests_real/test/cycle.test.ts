import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { newClient } from './real-server-adapter.ts';

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

// The schema has User.posts: [Post!] and Post.author: User! — a cycle.
// The generator breaks it by expanding author's fields inline inside
// _all_fields_Post rather than recursing back to ..._all_fields_User.

describe('User.posts — cycle User → Post → User (user-with-posts)', () => {
  it('User.posts is deserialized as an array', async () => {
    const res = await client.queries.getUser({ id: 'user-with-posts' });
    expect(res.getUser.posts).not.toBeNull();
    expect(Array.isArray(res.getUser.posts)).toBe(true);
  });

  it('User.posts list has 1 post', async () => {
    const res = await client.queries.getUser({ id: 'user-with-posts' });
    expect(res.getUser.posts!.length).toBe(1);
  });

  it('User.posts[0] has correct scalar fields', async () => {
    const res = await client.queries.getUser({ id: 'user-with-posts' });
    const post = res.getUser.posts![0];
    expect(post.id).toBe('post-10');
    expect(post.title).toBe('Cyclic Post');
    expect(post.viewCount).toBe(7);
  });

  it('User.posts[0].author is deserialized (cycle broken at one level)', async () => {
    const res = await client.queries.getUser({ id: 'user-with-posts' });
    const author = res.getUser.posts![0].author;
    expect(author.id).toBe('user-1');
    expect(author.name).toBe('Alice Smith');
  });

  it('User.posts[0].author.address is accessible', async () => {
    const res = await client.queries.getUser({ id: 'user-with-posts' });
    expect(res.getUser.posts![0].author.address.city).toBe('Springfield');
  });

  it('User.posts is null for users without posts', async () => {
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.posts).toBeNull();
  });
});

describe('Post.author — cycle Post → User → Post (post-10)', () => {
  it('Post.author is a full User', async () => {
    const res = await client.queries.getPost({ id: 'post-10' });
    expect(res.getPost.author.id).toBe('user-1');
    expect(res.getPost.author.name).toBe('Alice Smith');
  });

  it('Post.author projected type has scalar fields accessible', async () => {
    const res = await client.queries.getPost({ id: 'post-10' });
    expect(res.getPost.author.email).toBe('alice@test.com');
  });
});
