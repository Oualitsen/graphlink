import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { UserStatus } from '../lib/generated/enums/user-status.js';
import { Priority } from '../lib/generated/enums/priority.js';
import type { CreateUserInput } from '../lib/generated/inputs/create-user-input.js';
import type { UpdateUserInput } from '../lib/generated/inputs/update-user-input.js';
import { MockAdapter, MockWsAdapter } from './mock-adapter.ts';
import { kUserAliceJson, kUserBobJson } from './fixtures.ts';

const minimalInput: CreateUserInput = {
  name: 'Alice Smith',
  email: 'alice@test.com',
  status: UserStatus.Active,
  address: { street: '123 Main St', city: 'Springfield', country: 'US' },
};

let adapter: MockAdapter;
let client: GraphLinkClient;

beforeEach(() => {
  adapter = new MockAdapter();
  client = new GraphLinkClient(adapter.call, new MockWsAdapter());
});

// ── createUser — response deserialization ─────────────────────────────────────

describe('createUser — scalar fields', () => {
  beforeEach(() => { adapter.registerData('createUser', { createUser: kUserAliceJson }); });

  it('id is deserialized correctly', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.id).toBe('user-1');
  });

  it('name is deserialized correctly', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.name).toBe('Alice Smith');
  });

  it('email is deserialized correctly', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.email).toBe('alice@test.com');
  });

  it('status is deserialized as enum', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.status).toBe(UserStatus.Active);
  });

  it('priority is deserialized as enum when present', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.priority).toBe(Priority.High);
  });
});

describe('createUser — nested address', () => {
  beforeEach(() => { adapter.registerData('createUser', { createUser: kUserAliceJson }); });

  it('address.street is deserialized', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.address.street).toBe('123 Main St');
  });

  it('address.city is deserialized', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.address.city).toBe('Springfield');
  });

  it('address.country is deserialized', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.address.country).toBe('US');
  });

  it('address.zip is deserialized', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.address.zip).toBe('12345');
  });

  it('nullable billingAddress is null', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.billingAddress).toBeNull();
  });
});

describe('createUser — list fields', () => {
  beforeEach(() => { adapter.registerData('createUser', { createUser: kUserAliceJson }); });

  it('tags list is deserialized', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.tags).toEqual(['admin', 'beta']);
  });

  it('scores list is deserialized', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.scores).toEqual([10, 20, 30]);
  });
});

describe('createUser — response with Bob (nullable fields populated)', () => {
  beforeEach(() => { adapter.registerData('createUser', { createUser: kUserBobJson }); });

  it('status INACTIVE is deserialized', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.status).toBe(UserStatus.Inactive);
  });

  it('nullable priority is null', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.priority).toBeNull();
  });

  it('billingAddress is deserialized when present', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.billingAddress).not.toBeNull();
    expect(res.createUser.billingAddress!.city).toBe('Capital City');
  });

  it('empty tags list is deserialized as empty list', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.tags).toHaveLength(0);
  });

  it('nullable scores is null', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.scores).toBeNull();
  });
});

describe('createUser — outgoing request shape', () => {
  beforeEach(() => { adapter.registerData('createUser', { createUser: kUserAliceJson }); });

  it('operation name is createUser', async () => {
    await client.mutations.createUser({ input: minimalInput });
    expect(adapter.lastCall!.operationName).toBe('createUser');
  });

  it('input variable is present', async () => {
    await client.mutations.createUser({ input: minimalInput });
    expect(adapter.lastCall!.variables['input']).not.toBeNull();
  });
});

// ── deleteUser ────────────────────────────────────────────────────────────────

describe('deleteUser — returns bool', () => {
  it('returns true when server responds true', async () => {
    adapter.registerData('deleteUser', { deleteUser: true });
    const res = await client.mutations.deleteUser({ id: 'user-1' });
    expect(res.deleteUser).toBe(true);
  });

  it('returns false when server responds false', async () => {
    adapter.registerData('deleteUser', { deleteUser: false });
    const res = await client.mutations.deleteUser({ id: 'user-1' });
    expect(res.deleteUser).toBe(false);
  });
});

describe('deleteUser — outgoing request shape', () => {
  beforeEach(() => { adapter.registerData('deleteUser', { deleteUser: true }); });

  it('id variable is sent correctly', async () => {
    await client.mutations.deleteUser({ id: 'user-99' });
    expect(adapter.lastCall!.variables['id']).toBe('user-99');
  });

  it('operation name is deleteUser', async () => {
    await client.mutations.deleteUser({ id: 'user-1' });
    expect(adapter.lastCall!.operationName).toBe('deleteUser');
  });
});

// ── updateUser ────────────────────────────────────────────────────────────────

describe('updateUser — response deserialization', () => {
  beforeEach(() => { adapter.registerData('updateUser', { updateUser: kUserAliceJson }); });

  it('returns a User with correct id', async () => {
    const res = await client.mutations.updateUser({ id: 'user-1', input: { name: 'Alice Smith' } as UpdateUserInput });
    expect(res.updateUser.id).toBe('user-1');
  });

  it('returns a User with correct name', async () => {
    const res = await client.mutations.updateUser({ id: 'user-1', input: { name: 'Alice Smith' } as UpdateUserInput });
    expect(res.updateUser.name).toBe('Alice Smith');
  });

  it('status is deserialized as enum', async () => {
    const res = await client.mutations.updateUser({ id: 'user-1', input: { status: UserStatus.Active } });
    expect(res.updateUser.status).toBe(UserStatus.Active);
  });

  it('nested address is deserialized', async () => {
    const res = await client.mutations.updateUser({ id: 'user-1', input: { name: 'Alice Smith' } as UpdateUserInput });
    expect(res.updateUser.address.street).toBe('123 Main St');
  });
});

describe('updateUser — outgoing request shape', () => {
  beforeEach(() => { adapter.registerData('updateUser', { updateUser: kUserAliceJson }); });

  it('id is passed as top-level variable', async () => {
    await client.mutations.updateUser({ id: 'user-42', input: { name: 'Updated' } as UpdateUserInput });
    expect(adapter.lastCall!.variables['id']).toBe('user-42');
  });

  it('input variable is present alongside id', async () => {
    await client.mutations.updateUser({ id: 'user-1', input: { name: 'Updated' } as UpdateUserInput });
    expect(adapter.lastCall!.variables['input']).not.toBeNull();
  });

  it('operation name is updateUser', async () => {
    await client.mutations.updateUser({ id: 'user-1', input: { name: 'Updated' } as UpdateUserInput });
    expect(adapter.lastCall!.operationName).toBe('updateUser');
  });
});
