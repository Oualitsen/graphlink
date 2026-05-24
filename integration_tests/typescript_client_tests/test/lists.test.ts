import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { UserStatus } from '../lib/generated/enums/user-status.js';
import { MockAdapter, MockWsAdapter } from './mock-adapter.ts';
import { kUserAliceJson, kUserBobJson, kTagsJson } from './fixtures.ts';

let adapter: MockAdapter;
let client: GraphLinkClient;

beforeEach(() => {
  adapter = new MockAdapter();
  client = new GraphLinkClient(adapter.call, new MockWsAdapter());
});

describe('non-nullable list of objects', () => {
  it('listUsers returns a correctly typed list', async () => {
    adapter.registerData('listUsers', { listUsers: [kUserAliceJson, kUserBobJson] });
    const res = await client.queries.listUsers();
    expect(res.listUsers.length).toBe(2);
    expect(res.listUsers[0].id).toBe('user-1');
    expect(res.listUsers[1].id).toBe('user-2');
  });

  it('empty list is returned as empty list, not null', async () => {
    adapter.registerData('listUsers', { listUsers: [] });
    const res = await client.queries.listUsers();
    expect(res.listUsers).not.toBeNull();
    expect(res.listUsers).toHaveLength(0);
  });

  it('each item in the list is fully deserialized', async () => {
    adapter.registerData('listUsers', { listUsers: [kUserAliceJson] });
    const res = await client.queries.listUsers();
    expect(res.listUsers[0].name).toBe('Alice Smith');
    expect(res.listUsers[0].address.city).toBe('Springfield');
  });
});

describe('list of scalars on a type', () => {
  it('User.tags list deserializes correctly', async () => {
    adapter.registerData('getUser', { getUser: kUserAliceJson });
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.tags).toEqual(['admin', 'beta']);
  });

  it('empty tags list is empty, not null', async () => {
    adapter.registerData('getUser', { getUser: kUserBobJson });
    const res = await client.queries.getUser({ id: 'user-2' });
    expect(res.getUser.tags).toHaveLength(0);
  });

  it('nullable scores list is null when server returns null', async () => {
    adapter.registerData('getUser', { getUser: kUserBobJson });
    const res = await client.queries.getUser({ id: 'user-2' });
    expect(res.getUser.scores).toBeNull();
  });

  it('nullable scores list has values when server returns them', async () => {
    adapter.registerData('getUser', { getUser: kUserAliceJson });
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.scores).toEqual([10, 20, 30]);
  });
});

describe('list of objects with nullable fields', () => {
  it('getTags returns tags with nullable color field', async () => {
    adapter.registerData('getTags', { getTags: kTagsJson });
    const res = await client.queries.getTags();
    expect(res.getTags).toHaveLength(2);
    expect(res.getTags[0].label).toBe('dart');
    expect(res.getTags[0].color).toBe('#0175C2');
    expect(res.getTags[1].color).toBeNull();
  });
});

describe('list query with enum argument', () => {
  it('listUsersByStatus sends enum as string variable', async () => {
    adapter.registerData('listUsersByStatus', { listUsersByStatus: [] });
    await client.queries.listUsersByStatus({ status: UserStatus.ACTIVE });
    expect(adapter.lastCall!.variables['status']).toBe('ACTIVE');
  });
});
