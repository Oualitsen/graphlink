import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { newClient } from './real-server-adapter.ts';

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

describe('non-nullable query return', () => {
  it('getUser returns a non-null User with correct id', async () => {
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser).not.toBeNull();
    expect(res.getUser.id).toBe('user-1');
  });
});

describe('nullable query return', () => {
  it('findUser returns null for unknown id', async () => {
    const res = await client.queries.findUser({ id: 'missing' });
    expect(res.findUser).toBeNull();
  });

  it('findUser returns a User for known id', async () => {
    const res = await client.queries.findUser({ id: 'user-1' });
    expect(res.findUser).not.toBeNull();
    expect(res.findUser!.name).toBe('Alice Smith');
  });
});

describe('nullable nested object fields', () => {
  it('billingAddress is null for Alice', async () => {
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.billingAddress).toBeNull();
  });

  it('billingAddress is non-null for Bob', async () => {
    const res = await client.queries.getUser({ id: 'user-2' });
    expect(res.getUser.billingAddress).not.toBeNull();
    expect(res.getUser.billingAddress!.city).toBe('Capital City');
  });

  it('coAuthor on Post is null when absent', async () => {
    const res = await client.queries.getPost({ id: 'post-1' });
    expect(res.getPost.coAuthor).toBeNull();
  });

  it('coAuthor on Post is non-null when present', async () => {
    const res = await client.queries.getPost({ id: 'post-2' });
    expect(res.getPost.coAuthor).not.toBeNull();
    expect(res.getPost.coAuthor!.id).toBe('user-2');
  });
});

describe('nullable scalar fields on nested type', () => {
  it('Address.zip is null for Bob (no zip)', async () => {
    const res = await client.queries.getUser({ id: 'user-2' });
    expect(res.getUser.address.zip).toBeNull();
  });

  it('Address.zip has value for Alice', async () => {
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.address.zip).toBe('12345');
  });
});

describe('nullable list fields', () => {
  it('scores is null for Bob', async () => {
    const res = await client.queries.getUser({ id: 'user-2' });
    expect(res.getUser.scores).toBeNull();
  });

  it('scores is non-null for Alice', async () => {
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.scores).not.toBeNull();
    expect(res.getUser.scores).toEqual([10, 20, 30]);
  });
});
