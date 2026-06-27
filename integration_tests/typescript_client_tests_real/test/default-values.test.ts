import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { Role } from '../lib/generated/enums/role.js';
import { defaultCreateWithDefaultsInput } from '../lib/generated/inputs/create-with-defaults-input.js';
import { defaultNestedDefaultsInput } from '../lib/generated/inputs/nested-defaults-input.js';
import { defaultGetDriverFieldArgs } from '../lib/generated/inputs/get-driver-field-args.js';
import type { CreateWithDefaultsInput } from '../lib/generated/inputs/create-with-defaults-input.js';
import type { NestedDefaultsInput } from '../lib/generated/inputs/nested-defaults-input.js';
import type { GetDriverFieldArgs } from '../lib/generated/inputs/get-driver-field-args.js';
import { newClient } from './real-server-adapter.ts';

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

// ── Companion consts ──────────────────────────────────────────────────────────

describe('defaultCreateWithDefaultsInput companion const', () => {
  it('has correct Role.USER default', () => {
    expect(defaultCreateWithDefaultsInput.role).toBe(Role.USER);
  });

  it('has correct age default', () => {
    expect(defaultCreateWithDefaultsInput.age).toBe(18);
  });

  it('has correct isActive default', () => {
    expect(defaultCreateWithDefaultsInput.isActive).toBe(true);
  });

  it('has correct score default', () => {
    expect(defaultCreateWithDefaultsInput.score).toBe(4.5);
  });

  it('has correct nickname default', () => {
    expect(defaultCreateWithDefaultsInput.nickname).toBe('anonymous');
  });

  it('has correct tags default', () => {
    expect(defaultCreateWithDefaultsInput.tags).toEqual(['dart', 'graphql']);
  });
});

describe('defaultNestedDefaultsInput companion const', () => {
  it('has correct address object default', () => {
    expect(defaultNestedDefaultsInput.address).toEqual({
      street: '123 Main St',
      city: 'Springfield',
      country: 'US',
      zip: '12345',
    });
  });

  it('has correct contacts list-of-objects default', () => {
    expect(defaultNestedDefaultsInput.contacts).toEqual([
      { street: '456 Oak Ave', city: 'Shelbyville', country: 'US', zip: null },
      { street: '789 Pine Rd', city: 'Capital City', country: 'US', zip: '99999' },
    ]);
  });

  it('has correct matrix list-of-list-of-objects default', () => {
    expect(defaultNestedDefaultsInput.matrix).toEqual([
      [{ street: '1st St', city: 'Paris', country: 'FR', zip: '75000' }],
      [{ street: '2nd St', city: 'Lyon', country: 'FR', zip: '69000' }],
    ]);
  });
});

// ── listUsersWithDefaults — operation argument defaults ──────────────────────

describe('listUsersWithDefaults — client applies argument defaults', () => {
  it('returns users without providing optional arguments', async () => {
    const res = await client.queries.listUsersWithDefaults({});
    expect(res.listUsersWithDefaults.length).toBeGreaterThan(0);
  });

  it('explicit limit overrides default', async () => {
    const res = await client.queries.listUsersWithDefaults({ limit: 1 });
    expect(res.listUsersWithDefaults).toHaveLength(1);
  });

  it('explicit role can be provided', async () => {
    const res = await client.queries.listUsersWithDefaults({ role: Role.ADMIN });
    expect(res.listUsersWithDefaults.length).toBeGreaterThan(0);
  });
});

// ── createWithDefaults — input field defaults (companion const spread) ───────

describe('createWithDefaults — input field defaults applied via companion const', () => {
  function input(overrides: Partial<CreateWithDefaultsInput> = {}): CreateWithDefaultsInput {
    return { ...defaultCreateWithDefaultsInput, ...overrides } as CreateWithDefaultsInput;
  }

  it('role defaults to USER when using companion const', async () => {
    const res = await client.mutations.createWithDefaults({ input: input({ name: 'test' }) });
    expect(res.createWithDefaults.role).toBe(Role.USER);
  });

  it('age defaults to 18 when using companion const', async () => {
    const res = await client.mutations.createWithDefaults({ input: input({ name: 'test' }) });
    expect(res.createWithDefaults.age).toBe(18);
  });

  it('isActive defaults to true when using companion const', async () => {
    const res = await client.mutations.createWithDefaults({ input: input({ name: 'test' }) });
    expect(res.createWithDefaults.isActive).toBe(true);
  });

  it('score defaults to 4.5 when using companion const', async () => {
    const res = await client.mutations.createWithDefaults({ input: input({ name: 'test' }) });
    expect(res.createWithDefaults.score).toBe(4.5);
  });

  it('nickname defaults to "anonymous" when using companion const', async () => {
    const res = await client.mutations.createWithDefaults({ input: input({ name: 'test' }) });
    expect(res.createWithDefaults.nickname).toBe('anonymous');
  });

  it('tags defaults to ["dart", "graphql"] when using companion const', async () => {
    const res = await client.mutations.createWithDefaults({ input: input({ name: 'test' }) });
    expect(res.createWithDefaults.tags).toEqual(['dart', 'graphql']);
  });

  it('name is echoed from provided value', async () => {
    const res = await client.mutations.createWithDefaults({ input: input({ name: 'explicit-name' }) });
    expect(res.createWithDefaults.name).toBe('explicit-name');
  });

  it('explicit values override defaults', async () => {
    const res = await client.mutations.createWithDefaults({
      input: input({
        name: 'override-test',
        role: Role.ADMIN,
        age: 99,
        isActive: false,
        score: 9.9,
        nickname: 'custom',
        tags: ['custom-tag'],
      }),
    });
    expect(res.createWithDefaults.name).toBe('override-test');
    expect(res.createWithDefaults.role).toBe(Role.ADMIN);
    expect(res.createWithDefaults.age).toBe(99);
    expect(res.createWithDefaults.isActive).toBe(false);
    expect(res.createWithDefaults.score).toBe(9.9);
    expect(res.createWithDefaults.nickname).toBe('custom');
    expect(res.createWithDefaults.tags).toEqual(['custom-tag']);
  });
});

// ── createWithNestedDefaults — nested object/list defaults ───────────────────

describe('createWithNestedDefaults — nested defaults applied via companion const', () => {
  function input(overrides: Partial<NestedDefaultsInput> = {}): NestedDefaultsInput {
    return { ...defaultNestedDefaultsInput, ...overrides } as NestedDefaultsInput;
  }

  it('name is echoed from provided value', async () => {
    const res = await client.mutations.createWithNestedDefaults({ input: input({ name: 'nested-test' }) });
    expect(res.createWithNestedDefaults.name).toBe('nested-test');
  });

  // ── Object default ────────────────────────────────────────────────────────

  it('address defaults to full object', async () => {
    const res = await client.mutations.createWithNestedDefaults({ input: input({ name: 'obj-default' }) });
    expect(res.createWithNestedDefaults.address).not.toBeNull();
    expect(res.createWithNestedDefaults.address!.street).toBe('123 Main St');
    expect(res.createWithNestedDefaults.address!.city).toBe('Springfield');
    expect(res.createWithNestedDefaults.address!.country).toBe('US');
    expect(res.createWithNestedDefaults.address!.zip).toBe('12345');
  });

  // ── List-of-objects default ───────────────────────────────────────────────

  it('contacts defaults to list of two objects', async () => {
    const res = await client.mutations.createWithNestedDefaults({ input: input({ name: 'list-default' }) });
    expect(res.createWithNestedDefaults.contacts).not.toBeNull();
    expect(res.createWithNestedDefaults.contacts!).toHaveLength(2);
    expect(res.createWithNestedDefaults.contacts![0]!.street).toBe('456 Oak Ave');
    expect(res.createWithNestedDefaults.contacts![0]!.city).toBe('Shelbyville');
    expect(res.createWithNestedDefaults.contacts![0]!.zip).toBeNull();
    expect(res.createWithNestedDefaults.contacts![1]!.street).toBe('789 Pine Rd');
    expect(res.createWithNestedDefaults.contacts![1]!.city).toBe('Capital City');
    expect(res.createWithNestedDefaults.contacts![1]!.zip).toBe('99999');
  });

  // ── List-of-list-of-objects default ───────────────────────────────────────

  it('matrix defaults to nested list of objects', async () => {
    const res = await client.mutations.createWithNestedDefaults({ input: input({ name: 'matrix-default' }) });
    expect(res.createWithNestedDefaults.matrix).not.toBeNull();
    expect(res.createWithNestedDefaults.matrix!).toHaveLength(2);
    // Row 0: single address
    expect(res.createWithNestedDefaults.matrix![0]).toHaveLength(1);
    expect(res.createWithNestedDefaults.matrix![0]![0]!.street).toBe('1st St');
    expect(res.createWithNestedDefaults.matrix![0]![0]!.city).toBe('Paris');
    expect(res.createWithNestedDefaults.matrix![0]![0]!.country).toBe('FR');
    expect(res.createWithNestedDefaults.matrix![0]![0]!.zip).toBe('75000');
    // Row 1: single address
    expect(res.createWithNestedDefaults.matrix![1]).toHaveLength(1);
    expect(res.createWithNestedDefaults.matrix![1]![0]!.street).toBe('2nd St');
    expect(res.createWithNestedDefaults.matrix![1]![0]!.city).toBe('Lyon');
    expect(res.createWithNestedDefaults.matrix![1]![0]!.country).toBe('FR');
    expect(res.createWithNestedDefaults.matrix![1]![0]!.zip).toBe('69000');
  });

  // ── Explicit values override defaults ─────────────────────────────────────

  it('explicit values override nested defaults', async () => {
    const res = await client.mutations.createWithNestedDefaults({
      input: input({
        name: 'override-nested',
        address: { street: 'Custom St', city: 'Custom City', country: 'XX', zip: null },
        contacts: [
          { street: 'One', city: 'Two', country: 'Three', zip: '44444' },
        ],
        matrix: [
          [{ street: 'A', city: 'B', country: 'C', zip: null }],
        ],
      }),
    });
    expect(res.createWithNestedDefaults.address).not.toBeNull();
    expect(res.createWithNestedDefaults.address!.street).toBe('Custom St');
    expect(res.createWithNestedDefaults.address!.city).toBe('Custom City');
    expect(res.createWithNestedDefaults.address!.country).toBe('XX');
    expect(res.createWithNestedDefaults.address!.zip).toBeNull();

    expect(res.createWithNestedDefaults.contacts!).toHaveLength(1);
    expect(res.createWithNestedDefaults.contacts![0]!.street).toBe('One');

    expect(res.createWithNestedDefaults.matrix!).toHaveLength(1);
    expect(res.createWithNestedDefaults.matrix![0]![0]!.street).toBe('A');
  });
});

// ── getDriver — field-argument defaults ──────────────────────────────────────

describe('getDriver — client applies field-argument defaults', () => {
  function fieldArgs(overrides: Partial<GetDriverFieldArgs> = {}): GetDriverFieldArgs {
    return { ...defaultGetDriverFieldArgs, ...overrides } as GetDriverFieldArgs;
  }

  it('odometerKm is required and echoed back', async () => {
    const res = await client.queries.getDriver({ id: 'driver-1', fieldArgs: fieldArgs({ lastUsedMillageOdometerKm: 100 }) });
    expect(res.getDriver.lastUsedMillage).toBe(100);
  });

  it('liters defaults to 4 when not provided', async () => {
    const res = await client.queries.getDriver({ id: 'driver-1', fieldArgs: fieldArgs({ lastUsedMillageOdometerKm: 200 }) });
    expect(res.getDriver.lastUsedFuel).toBe(4);
  });

  it('explicit liters overrides the default', async () => {
    const res = await client.queries.getDriver({ id: 'driver-1', fieldArgs: fieldArgs({ lastUsedMillageOdometerKm: 300, lastUsedFuelLiters: 10 }) });
    expect(res.getDriver.lastUsedFuel).toBe(10);
  });

  it('both values echoed back with explicit liters', async () => {
    const res = await client.queries.getDriver({ id: 'driver-1', fieldArgs: fieldArgs({ lastUsedMillageOdometerKm: 500, lastUsedFuelLiters: 25 }) });
    expect(res.getDriver.lastUsedMillage).toBe(500);
    expect(res.getDriver.lastUsedFuel).toBe(25);
  });
});
