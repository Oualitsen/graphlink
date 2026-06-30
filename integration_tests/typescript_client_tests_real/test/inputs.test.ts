// Input serialization is verified via round-trip: the server echoes back whatever
// we send in CreateUserInput / UpdateUserInput, so correct deserialization of the
// response proves the input was serialized correctly.
import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { UserStatus } from '../lib/generated/enums/user-status.js';
import { Priority } from '../lib/generated/enums/priority.js';
import type { CreateUserInput } from '../lib/generated/inputs/create-user-input.js';
import type { UpdateUserInput } from '../lib/generated/inputs/update-user-input.js';
import type { AddressInput } from '../lib/generated/inputs/address-input.js';
import { newClient } from './real-server-adapter.ts';

const minimalAddress: AddressInput = { street: '123 Main St', city: 'Springfield', country: 'US' };
const minimalInput: CreateUserInput = {
  name: 'Alice Smith',
  email: 'alice@test.com',
  status: UserStatus.Active,
  address: minimalAddress,
};

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

describe('CreateUserInput — required scalar fields echoed in response', () => {
  it('name is serialized and echoed', async () => {
    const res = await client.mutations.createUser({ input: { ...minimalInput, name: 'Test User' } });
    expect(res.createUser.name).toBe('Test User');
  });

  it('email is serialized and echoed', async () => {
    const res = await client.mutations.createUser({ input: { ...minimalInput, email: 'test@example.com' } });
    expect(res.createUser.email).toBe('test@example.com');
  });

  it('enum status SUSPENDED is serialized and echoed', async () => {
    const res = await client.mutations.createUser({ input: { ...minimalInput, status: UserStatus.Suspended } });
    expect(res.createUser.status).toBe(UserStatus.Suspended);
  });
});

describe('CreateUserInput — nested AddressInput echoed in response', () => {
  it('address fields are serialized correctly', async () => {
    const res = await client.mutations.createUser({
      input: { ...minimalInput, address: { street: '456 Oak Ave', city: 'Shelbyville', country: 'UK', zip: '99999' } },
    });
    expect(res.createUser.address.street).toBe('456 Oak Ave');
    expect(res.createUser.address.city).toBe('Shelbyville');
    expect(res.createUser.address.country).toBe('UK');
    expect(res.createUser.address.zip).toBe('99999');
  });

  it('nullable zip is null when not provided', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.address.zip).toBeNull();
  });
});

describe('CreateUserInput — optional fields', () => {
  it('priority is null when not provided', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.priority).toBeNull();
  });

  it('priority CRITICAL is serialized and echoed', async () => {
    const res = await client.mutations.createUser({ input: { ...minimalInput, priority: Priority.Critical } });
    expect(res.createUser.priority).toBe(Priority.Critical);
  });

  it('billingAddress is null when not provided', async () => {
    const res = await client.mutations.createUser({ input: minimalInput });
    expect(res.createUser.billingAddress).toBeNull();
  });

  it('tags list is serialized and echoed', async () => {
    const res = await client.mutations.createUser({ input: { ...minimalInput, tags: ['admin', 'beta'] } });
    expect(res.createUser.tags).toEqual(['admin', 'beta']);
  });

  it('empty tags list is serialized as empty list', async () => {
    const res = await client.mutations.createUser({ input: { ...minimalInput, tags: [] } });
    expect(res.createUser.tags).toHaveLength(0);
  });
});

describe('UpdateUserInput — nullable fields round-trip', () => {
  it('updated name is reflected in response', async () => {
    const res = await client.mutations.updateUser({ id: 'user-1', input: { name: 'New Name' } as UpdateUserInput });
    expect(res.updateUser.name).toBe('New Name');
    expect(res.updateUser.id).toBe('user-1');
  });

  it('other fields preserved when only name is updated', async () => {
    const res = await client.mutations.updateUser({ id: 'user-1', input: { name: 'Alice Smith' } as UpdateUserInput });
    expect(res.updateUser.status).toBe(UserStatus.Active);
    expect(res.updateUser.address.street).toBe('123 Main St');
  });

  it('status update is reflected in response', async () => {
    const res = await client.mutations.updateUser({ id: 'user-1', input: { status: UserStatus.Inactive } });
    expect(res.updateUser.status).toBe(UserStatus.Inactive);
  });
});
