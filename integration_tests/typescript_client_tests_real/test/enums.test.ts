import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { UserStatus } from '../lib/generated/enums/user-status.js';
import { Priority } from '../lib/generated/enums/priority.js';
import { newClient } from './real-server-adapter.ts';

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

describe('enum deserialization', () => {
  it('ACTIVE deserializes to UserStatus.Active', async () => {
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.status).toBe(UserStatus.Active);
  });

  it('INACTIVE deserializes to UserStatus.Inactive', async () => {
    const res = await client.queries.getUser({ id: 'user-2' });
    expect(res.getUser.status).toBe(UserStatus.Inactive);
  });

  it('HIGH deserializes to Priority.High', async () => {
    const res = await client.queries.getUser({ id: 'user-1' });
    expect(res.getUser.priority).toBe(Priority.High);
  });

  it('nullable enum is null when server returns null', async () => {
    const res = await client.queries.getUser({ id: 'user-2' });
    expect(res.getUser.priority).toBeNull();
  });
});

describe('enum in list response', () => {
  it('listUsers contains correctly deserialized statuses', async () => {
    const res = await client.queries.listUsers();
    const alice = res.listUsers.find(u => u.id === 'user-1');
    const bob = res.listUsers.find(u => u.id === 'user-2');
    expect(alice?.status).toBe(UserStatus.Active);
    expect(bob?.status).toBe(UserStatus.Inactive);
  });
});

describe('enum filtering via listUsersByStatus', () => {
  it('ACTIVE returns only Alice', async () => {
    const res = await client.queries.listUsersByStatus({ status: UserStatus.Active });
    expect(res.listUsersByStatus).toHaveLength(1);
    expect(res.listUsersByStatus[0].id).toBe('user-1');
  });

  it('INACTIVE returns only Bob', async () => {
    const res = await client.queries.listUsersByStatus({ status: UserStatus.Inactive });
    expect(res.listUsersByStatus).toHaveLength(1);
    expect(res.listUsersByStatus[0].id).toBe('user-2');
  });

  it('SUSPENDED returns empty list', async () => {
    const res = await client.queries.listUsersByStatus({ status: UserStatus.Suspended });
    expect(res.listUsersByStatus).toHaveLength(0);
  });
});
