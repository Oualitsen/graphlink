import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { UserStatus } from '../lib/generated/enums/user-status.js';
import { Priority } from '../lib/generated/enums/priority.js';
import { MockAdapter, MockWsAdapter } from './mock-adapter.ts';
import { kUserAliceJson, kUserBobJson } from './fixtures.ts';

let adapter: MockAdapter;
let client: GraphLinkClient;

beforeEach(() => {
  adapter = new MockAdapter();
  client = new GraphLinkClient(adapter.call, new MockWsAdapter());
});

describe('enum deserialization', () => {
  it('ACTIVE deserializes to UserStatus.ACTIVE', async () => {
    adapter.registerData('getUser', { getUser: kUserAliceJson });
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.status).toBe(UserStatus.ACTIVE);
  });

  it('INACTIVE deserializes to UserStatus.INACTIVE', async () => {
    adapter.registerData('getUser', { getUser: kUserBobJson });
    const res = await client.queries.getUser({ id: 'user-2' });
    expect(res.getUser.status).toBe(UserStatus.INACTIVE);
  });

  it('HIGH deserializes to Priority.HIGH', async () => {
    adapter.registerData('getUser', { getUser: kUserAliceJson });
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.priority).toBe(Priority.HIGH);
  });

  it('nullable enum is null when server returns null', async () => {
    adapter.registerData('getUser', { getUser: kUserBobJson });
    const res = await client.queries.getUser({ id: 'user-2' });
    expect(res.getUser.priority).toBeNull();
  });
});

describe('enum serialization in query variables', () => {
  beforeEach(() => {
    adapter.registerData('listUsersByStatus', { listUsersByStatus: [] });
  });

  it('UserStatus.ACTIVE is serialized as "ACTIVE" in variables', async () => {
    await client.queries.listUsersByStatus({ status: UserStatus.ACTIVE });
    expect(adapter.lastCall?.variables['status']).toBe('ACTIVE');
  });

  it('UserStatus.INACTIVE is serialized as "INACTIVE" in variables', async () => {
    await client.queries.listUsersByStatus({ status: UserStatus.INACTIVE });
    expect(adapter.lastCall?.variables['status']).toBe('INACTIVE');
  });

  it('UserStatus.SUSPENDED is serialized as "SUSPENDED" in variables', async () => {
    await client.queries.listUsersByStatus({ status: UserStatus.SUSPENDED });
    expect(adapter.lastCall?.variables['status']).toBe('SUSPENDED');
  });
});

describe('enum in list response', () => {
  it('list of users contains correctly deserialized statuses', async () => {
    adapter.registerData('listUsers', { listUsers: [kUserAliceJson, kUserBobJson] });
    const res = await client.queries.listUsers();
    expect(res.listUsers[0].status).toBe(UserStatus.ACTIVE);
    expect(res.listUsers[1].status).toBe(UserStatus.INACTIVE);
  });
});
