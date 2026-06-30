import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { UserStatus } from '../lib/generated/enums/user-status.js';
import { newClient } from './real-server-adapter.ts';

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

describe('non-nullable list of objects', () => {
  it('listUsers returns 2 users', async () => {
    const res = await client.queries.listUsers();
    expect(res.listUsers).toHaveLength(2);
  });

  it('listUsers items have correct ids', async () => {
    const res = await client.queries.listUsers();
    expect(res.listUsers[0].id).toBe('user-1');
    expect(res.listUsers[1].id).toBe('user-2');
  });

  it('each item is fully deserialized', async () => {
    const res = await client.queries.listUsers();
    expect(res.listUsers[0].name).toBe('Alice Smith');
    expect(res.listUsers[0].address.city).toBe('Springfield');
  });
});

describe('list of scalars on a type', () => {
  it('User.tags list deserializes correctly for Alice', async () => {
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.tags).toEqual(['admin', 'beta']);
  });

  it('empty tags list for Bob', async () => {
    const res = await client.queries.getUser({ id: 'user-2' });
    expect(res.getUser.tags).toHaveLength(0);
  });

  it('nullable scores is null for Bob', async () => {
    const res = await client.queries.getUser({ id: 'user-2' });
    expect(res.getUser.scores).toBeNull();
  });

  it('nullable scores has values for Alice', async () => {
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.scores).toEqual([10, 20, 30]);
  });
});

describe('list of objects with nullable fields', () => {
  it('getTags returns 2 tags with correct fields', async () => {
    const res = await client.queries.getTags();
    expect(res.getTags).toHaveLength(2);
    expect(res.getTags[0].label).toBe('dart');
    expect(res.getTags[0].color).toBe('#0175C2');
    expect(res.getTags[1].color).toBeNull();
  });
});

describe('list query with enum argument', () => {
  it('listUsersByStatus(ACTIVE) returns only active users', async () => {
    const res = await client.queries.listUsersByStatus({ status: UserStatus.Active });
    expect(res.listUsersByStatus.every(u => u.status === UserStatus.Active)).toBe(true);
  });
});
