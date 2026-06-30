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
  it('ACTIVE deserializes to UserStatus.Active', async () => {
    adapter.registerData('getUser', { getUser: kUserAliceJson });
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.status).toBe(UserStatus.Active);
  });

  it('INACTIVE deserializes to UserStatus.Inactive', async () => {
    adapter.registerData('getUser', { getUser: kUserBobJson });
    const res = await client.queries.getUser({ id: 'user-2' });
    expect(res.getUser.status).toBe(UserStatus.Inactive);
  });

  it('HIGH deserializes to Priority.High', async () => {
    adapter.registerData('getUser', { getUser: kUserAliceJson });
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.priority).toBe(Priority.High);
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

  it('UserStatus.Active is serialized as "ACTIVE" in variables', async () => {
    await client.queries.listUsersByStatus({ status: UserStatus.Active });
    expect(adapter.lastCall?.variables['status']).toBe('ACTIVE');
  });

  it('UserStatus.Inactive is serialized as "INACTIVE" in variables', async () => {
    await client.queries.listUsersByStatus({ status: UserStatus.Inactive });
    expect(adapter.lastCall?.variables['status']).toBe('INACTIVE');
  });

  it('UserStatus.Suspended is serialized as "SUSPENDED" in variables', async () => {
    await client.queries.listUsersByStatus({ status: UserStatus.Suspended });
    expect(adapter.lastCall?.variables['status']).toBe('SUSPENDED');
  });
});

describe('enum in list response', () => {
  it('list of users contains correctly deserialized statuses', async () => {
    adapter.registerData('listUsers', { listUsers: [kUserAliceJson, kUserBobJson] });
    const res = await client.queries.listUsers();
    expect(res.listUsers[0].status).toBe(UserStatus.Active);
    expect(res.listUsers[1].status).toBe(UserStatus.Inactive);
  });
});
