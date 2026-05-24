import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { UserStatus } from '../lib/generated/enums/user-status.js';
import { Priority } from '../lib/generated/enums/priority.js';
import type { CreateUserInput } from '../lib/generated/inputs/create-user-input.js';
import type { UpdateUserInput } from '../lib/generated/inputs/update-user-input.js';
import type { AddressInput } from '../lib/generated/inputs/address-input.js';
import { MockAdapter, MockWsAdapter } from './mock-adapter.ts';
import { kUserAliceJson } from './fixtures.ts';

const minimalAddress: AddressInput = { street: '123 Main St', city: 'Springfield', country: 'US' };
const minimalInput: CreateUserInput = {
  name: 'Alice Smith',
  email: 'alice@test.com',
  status: UserStatus.ACTIVE,
  address: minimalAddress,
};

let adapter: MockAdapter;
let client: GraphLinkClient;

beforeEach(() => {
  adapter = new MockAdapter();
  client = new GraphLinkClient(adapter.call, new MockWsAdapter());
  adapter.registerData('createUser', { createUser: kUserAliceJson });
  adapter.registerData('updateUser', { updateUser: kUserAliceJson });
});

describe('CreateUserInput — required scalar fields', () => {
  it('name is serialized correctly', async () => {
    await client.mutations.createUser({ input: minimalInput });
    const input = adapter.lastCall!.variables['input'] as Record<string, unknown>;
    expect(input['name']).toBe('Alice Smith');
  });

  it('email is serialized correctly', async () => {
    await client.mutations.createUser({ input: minimalInput });
    const input = adapter.lastCall!.variables['input'] as Record<string, unknown>;
    expect(input['email']).toBe('alice@test.com');
  });

  it('enum field status is serialized as a string', async () => {
    await client.mutations.createUser({
      input: { ...minimalInput, status: UserStatus.SUSPENDED },
    });
    const input = adapter.lastCall!.variables['input'] as Record<string, unknown>;
    expect(input['status']).toBe('SUSPENDED');
  });
});

describe('CreateUserInput — nested AddressInput', () => {
  it('address fields are serialized correctly', async () => {
    await client.mutations.createUser({
      input: { ...minimalInput, address: { street: '123 Main St', city: 'Springfield', country: 'US', zip: '12345' } },
    });
    const input = adapter.lastCall!.variables['input'] as Record<string, unknown>;
    const address = input['address'] as Record<string, unknown>;
    expect(address['street']).toBe('123 Main St');
    expect(address['city']).toBe('Springfield');
    expect(address['country']).toBe('US');
    expect(address['zip']).toBe('12345');
  });

  it('nullable zip is null when not provided', async () => {
    await client.mutations.createUser({ input: minimalInput });
    const input = adapter.lastCall!.variables['input'] as Record<string, unknown>;
    const address = input['address'] as Record<string, unknown>;
    expect(address['zip'] ?? null).toBeNull();
  });
});

describe('CreateUserInput — optional fields', () => {
  it('nullable priority is null when not provided', async () => {
    await client.mutations.createUser({ input: minimalInput });
    const input = adapter.lastCall!.variables['input'] as Record<string, unknown>;
    expect(input['priority'] ?? null).toBeNull();
  });

  it('priority is serialized as string when provided', async () => {
    await client.mutations.createUser({ input: { ...minimalInput, priority: Priority.CRITICAL } });
    const input = adapter.lastCall!.variables['input'] as Record<string, unknown>;
    expect(input['priority']).toBe('CRITICAL');
  });

  it('billingAddress is null when not provided', async () => {
    await client.mutations.createUser({ input: minimalInput });
    const input = adapter.lastCall!.variables['input'] as Record<string, unknown>;
    expect(input['billingAddress'] ?? null).toBeNull();
  });

  it('tags list is serialized correctly', async () => {
    await client.mutations.createUser({ input: { ...minimalInput, tags: ['admin', 'beta'] } });
    const input = adapter.lastCall!.variables['input'] as Record<string, unknown>;
    expect(input['tags']).toEqual(['admin', 'beta']);
  });

  it('empty tags list is serialized as empty list', async () => {
    await client.mutations.createUser({ input: { ...minimalInput, tags: [] } });
    const input = adapter.lastCall!.variables['input'] as Record<string, unknown>;
    expect(input['tags']).toEqual([]);
  });
});

describe('UpdateUserInput — all nullable fields', () => {
  it('only provided fields are non-null in variables', async () => {
    await client.mutations.updateUser({ id: 'user-1', input: { name: 'New Name' } as UpdateUserInput });
    const input = adapter.lastCall!.variables['input'] as Record<string, unknown>;
    expect(input['name']).toBe('New Name');
    expect(input['email'] ?? null).toBeNull();
    expect(input['status'] ?? null).toBeNull();
  });

  it('id is passed correctly as a top-level variable', async () => {
    await client.mutations.updateUser({ id: 'user-42', input: { status: UserStatus.INACTIVE } });
    expect(adapter.lastCall!.variables['id']).toBe('user-42');
  });
});
