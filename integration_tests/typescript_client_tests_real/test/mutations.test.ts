import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { UserStatus } from '../lib/generated/enums/user-status.js';
import { Priority } from '../lib/generated/enums/priority.js';
import type { CreateUserInput } from '../lib/generated/inputs/create-user-input.js';
import type { UpdateUserInput } from '../lib/generated/inputs/update-user-input.js';
import { newClient } from './real-server-adapter.ts';

const minimalInput: CreateUserInput = {
  name: 'Alice Smith',
  email: 'alice@test.com',
  status: UserStatus.Active,
  address: { street: '123 Main St', city: 'Springfield', country: 'US' },
};

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

// ── createUser ────────────────────────────────────────────────────────────────

describe('createUser — scalar fields', () => {
  it('id is user-new', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.id).toBe('user-new');
  });

  it('name is echoed', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.name).toBe('Alice Smith');
  });

  it('email is echoed', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.email).toBe('alice@test.com');
  });

  it('status is deserialized as enum', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.status).toBe(UserStatus.Active);
  });

  it('priority is null when not in input', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.priority).toBeNull();
  });
});

describe('createUser — with optional fields', () => {
  it('priority is echoed when provided', async () => {
    const res = await client.mutations.createUser({ input: { ...minimalInput, priority: Priority.High } });
    expect(res.createUser.priority).toBe(Priority.High);
  });

  it('status INACTIVE is echoed', async () => {
    const res = await client.mutations.createUser({ input: { ...minimalInput, status: UserStatus.Inactive } });
    expect(res.createUser.status).toBe(UserStatus.Inactive);
  });
});

describe('createUser — nested address', () => {
  it('address fields are echoed', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.address.street).toBe('123 Main St');
    expect(res.createUser.address.city).toBe('Springfield');
    expect(res.createUser.address.country).toBe('US');
  });

  it('nullable billingAddress is null when not provided', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.billingAddress).toBeNull();
  });
});

describe('createUser — list fields', () => {
  it('tags is empty when not provided', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.tags).toHaveLength(0);
  });
});

// ── deleteUser ────────────────────────────────────────────────────────────────

describe('deleteUser — returns bool', () => {
  it('returns true', async () => {
    const res = await client.mutations.deleteUser({ id: 'user-1' });
    expect(res.deleteUser).toBe(true);
  });

  it('returns true regardless of id', async () => {
    const res = await client.mutations.deleteUser({ id: 'user-99' });
    expect(res.deleteUser).toBe(true);
  });
});

// ── updateUser ────────────────────────────────────────────────────────────────

describe('updateUser — response deserialization', () => {
  it('returns user with same id', async () => {
    const res = await client.mutations.updateUser({ id: 'user-1', input: { name: 'Updated Alice' } as UpdateUserInput });
    expect(res.updateUser.id).toBe('user-1');
  });

  it('name is updated', async () => {
    const res = await client.mutations.updateUser({ id: 'user-1', input: { name: 'Updated Alice' } as UpdateUserInput });
    expect(res.updateUser.name).toBe('Updated Alice');
  });

  it('status preserved when not in update input', async () => {
    const res = await client.mutations.updateUser({ id: 'user-1', input: { name: 'Alice Smith' } as UpdateUserInput });
    expect(res.updateUser.status).toBe(UserStatus.Active);
  });

  it('address preserved when not in update input', async () => {
    const res = await client.mutations.updateUser({ id: 'user-1', input: { name: 'Alice Smith' } as UpdateUserInput });
    expect(res.updateUser.address.street).toBe('123 Main St');
  });
});
