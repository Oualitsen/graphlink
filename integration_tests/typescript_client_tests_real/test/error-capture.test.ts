import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import type { GraphLinkError } from '../lib/generated/types/graph-link-error.js';
import { UserStatus } from '../lib/generated/enums/user-status.js';
import type { CreateUserInput } from '../lib/generated/inputs/create-user-input.js';
import { newClient } from './real-server-adapter.ts';

// Errors are triggered by special IDs / names the server special-cases:
//   getUser('error-id')              → throws (non-nullable field, data=null)
//   getUserOrErrors('error-id')      → errors captured, data=null
//   findUserOrErrors('error-id')     → errors captured, data.findUserOrErrors=null
//   createUserOrErrors(name='error-user') → errors captured, data=null

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

// ── getUserOrErrors — error response ──────────────────────────────────────────

describe('getUserOrErrors — error response (error-id)', () => {
  it('errors is non-null', async () => {
    const res = await client.queries.getUserOrErrors({ id: 'error-id' });
    expect(res.errors).not.toBeNull();
  });

  it('data is null', async () => {
    const res = await client.queries.getUserOrErrors({ id: 'error-id' });
    expect(res.data).toBeNull();
  });

  it('first error has a non-empty message', async () => {
    const res = await client.queries.getUserOrErrors({ id: 'error-id' });
    expect(res.errors![0].message).toBeTruthy();
  });
});

// ── getUserOrErrors — success response ────────────────────────────────────────

describe('getUserOrErrors — success response (user-1)', () => {
  it('errors is null', async () => {
    const res = await client.queries.getUserOrErrors({ id: 'user-1' });
    expect(res.errors).toBeNull();
  });

  it('data is non-null', async () => {
    const res = await client.queries.getUserOrErrors({ id: 'user-1' });
    expect(res.data).not.toBeNull();
  });

  it('data.getUserOrErrors.name is Alice Smith', async () => {
    const res = await client.queries.getUserOrErrors({ id: 'user-1' });
    expect(res.data!.getUserOrErrors.name).toBe('Alice Smith');
  });

  it('data.getUserOrErrors.id is user-1', async () => {
    const res = await client.queries.getUserOrErrors({ id: 'user-1' });
    expect(res.data!.getUserOrErrors.id).toBe('user-1');
  });
});

// ── findUserOrErrors — error response ─────────────────────────────────────────
// Spring returns partial data {findUserOrErrors: null} for nullable fields —
// so data is NOT null, but errors is populated.

describe('findUserOrErrors — error response (error-id)', () => {
  it('errors is non-null', async () => {
    const res = await client.queries.findUserOrErrors({ id: 'error-id' });
    expect(res.errors).not.toBeNull();
  });

  it('data.findUserOrErrors is null when error occurs', async () => {
    const res = await client.queries.findUserOrErrors({ id: 'error-id' });
    expect(res.data!.findUserOrErrors).toBeNull();
  });
});

// ── findUserOrErrors — null return (non-error unknown id) ─────────────────────

describe('findUserOrErrors — null return (missing non-error id)', () => {
  it('errors is null and data.findUserOrErrors is null', async () => {
    const res = await client.queries.findUserOrErrors({ id: 'missing' });
    expect(res.errors).toBeNull();
    expect(res.data!.findUserOrErrors).toBeNull();
  });
});

// ── createUserOrErrors — error response ───────────────────────────────────────

describe('createUserOrErrors — error response (error-user)', () => {
  const errorInput: CreateUserInput = {
    name: 'error-user',
    email: 'a@b.com',
    status: UserStatus.Active,
    address: { street: '1', city: 'C', country: 'US' },
  };

  it('errors is non-null', async () => {
    const res = await client.mutations.createUserOrErrors({ input: errorInput });
    expect(res.errors).not.toBeNull();
  });

  it('data is null', async () => {
    const res = await client.mutations.createUserOrErrors({ input: errorInput });
    expect(res.data).toBeNull();
  });
});

// ── createUserOrErrors — success response ─────────────────────────────────────

describe('createUserOrErrors — success response', () => {
  const goodInput: CreateUserInput = {
    name: 'Alice Smith',
    email: 'alice@test.com',
    status: UserStatus.Active,
    address: { street: '123 Main St', city: 'Springfield', country: 'US' },
  };

  it('errors is null', async () => {
    const res = await client.mutations.createUserOrErrors({ input: goodInput });
    expect(res.errors).toBeNull();
  });

  it('data is non-null', async () => {
    const res = await client.mutations.createUserOrErrors({ input: goodInput });
    expect(res.data).not.toBeNull();
  });

  it('data.createUserOrErrors.name is correct', async () => {
    const res = await client.mutations.createUserOrErrors({ input: goodInput });
    expect(res.data!.createUserOrErrors.name).toBe('Alice Smith');
  });
});

// ── getUser — no @glCaptureErrors: throws on error ────────────────────────────

describe('getUser — throws on error response', () => {
  it('throws a GraphLinkError[] when server returns errors', async () => {
    await expect(client.queries.getUser({ id: 'error-id' })).rejects.toSatisfy(
      (e): boolean => Array.isArray(e) && (e as GraphLinkError[])[0]?.message?.length > 0,
    );
  });

  it('thrown value is an array', async () => {
    let thrown: unknown;
    try {
      await client.queries.getUser({ id: 'error-id' });
    } catch (e) {
      thrown = e;
    }
    expect(Array.isArray(thrown)).toBe(true);
  });
});
