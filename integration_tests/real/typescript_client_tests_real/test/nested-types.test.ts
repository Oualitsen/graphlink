import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { newClient } from './real-server-adapter.ts';

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

describe('required nested object', () => {
  it('User.address is correctly deserialized', async () => {
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.address.street).toBe('123 Main St');
    expect(res.getUser.address.city).toBe('Springfield');
    expect(res.getUser.address.country).toBe('US');
    expect(res.getUser.address.zip).toBe('12345');
  });
});

describe('nullable nested object', () => {
  it('User.billingAddress is null for Alice', async () => {
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.billingAddress).toBeNull();
  });

  it('User.billingAddress is correctly deserialized for Bob', async () => {
    const res = await client.queries.getUser({ id: 'user-2' });
    expect(res.getUser.billingAddress).not.toBeNull();
    expect(res.getUser.billingAddress!.street).toBe('789 Pine Rd');
    expect(res.getUser.billingAddress!.city).toBe('Capital City');
    expect(res.getUser.billingAddress!.zip).toBe('99999');
  });
});

describe('multi-level nesting (Post → User → Address)', () => {
  it('Post.author is deserialized as a full User', async () => {
    const res = await client.queries.getPost({ id: 'post-1' });
    expect(res.getPost.author.id).toBe('user-1');
    expect(res.getPost.author.name).toBe('Alice Smith');
    expect(res.getPost.author.email).toBe('alice@test.com');
  });

  it('Post.author.address is accessible at three levels deep', async () => {
    const res = await client.queries.getPost({ id: 'post-1' });
    expect(res.getPost.author.address.city).toBe('Springfield');
  });

  it('Post.coAuthor is null for post-1', async () => {
    const res = await client.queries.getPost({ id: 'post-1' });
    expect(res.getPost.coAuthor).toBeNull();
  });

  it('Post scalar fields are deserialized correctly', async () => {
    const res = await client.queries.getPost({ id: 'post-1' });
    expect(res.getPost.title).toBe('Hello World');
    expect(res.getPost.viewCount).toBe(128);
  });
});

describe('@glSkipOnClient field excluded from generated type', () => {
  it('AuditEntry deserializes id and action; internalNote is not in the type', async () => {
    const res = await client.queries.getAuditEntry({ id: 'audit-2' });
    expect(res.getAuditEntry.id).toBe('audit-2');
    expect(res.getAuditEntry.action).toBe('LOGOUT');
    // Compile-time check: (res.getAuditEntry as any).internalNote is not typed
  });
});
