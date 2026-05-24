import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import type { GraphLinkError } from '../lib/generated/types/graph-link-error.js';
import { MockAdapter, MockWsAdapter } from './mock-adapter.ts';
import { kUserAliceJson, kGraphQLError } from './fixtures.ts';

let adapter: MockAdapter;
let client: GraphLinkClient;

beforeEach(() => {
  adapter = new MockAdapter();
  client = new GraphLinkClient(adapter.call, new MockWsAdapter());
});

// ── getUserOrErrors — error response ──────────────────────────────────────────

describe('getUserOrErrors — error response', () => {
  beforeEach(() => { adapter.registerErrors('getUserOrErrors', [kGraphQLError]); });

  it('errors is non-null', async () => {
    const res = await client.queries.getUserOrErrors({ id: 'user-1' });
    expect(res.errors).not.toBeNull();
  });

  it('data is null', async () => {
    const res = await client.queries.getUserOrErrors({ id: 'user-1' });
    expect(res.data).toBeNull();
  });

  it('first error has correct message', async () => {
    const res = await client.queries.getUserOrErrors({ id: 'user-1' });
    expect(res.errors![0].message).toBe('Not found');
  });
});

// ── getUserOrErrors — success response ────────────────────────────────────────

describe('getUserOrErrors — success response', () => {
  beforeEach(() => { adapter.registerData('getUserOrErrors', { getUserOrErrors: kUserAliceJson }); });

  it('errors is null', async () => {
    const res = await client.queries.getUserOrErrors({ id: 'user-1' });
    expect(res.errors).toBeNull();
  });

  it('data is non-null', async () => {
    const res = await client.queries.getUserOrErrors({ id: 'user-1' });
    expect(res.data).not.toBeNull();
  });

  it('data.getUserOrErrors.name is correct', async () => {
    const res = await client.queries.getUserOrErrors({ id: 'user-1' });
    expect(res.data!.getUserOrErrors.name).toBe('Alice Smith');
  });

  it('data.getUserOrErrors.id is correct', async () => {
    const res = await client.queries.getUserOrErrors({ id: 'user-1' });
    expect(res.data!.getUserOrErrors.id).toBe('user-1');
  });
});

// ── findUserOrErrors — error response ─────────────────────────────────────────

describe('findUserOrErrors — error response', () => {
  beforeEach(() => { adapter.registerErrors('findUserOrErrors', [kGraphQLError]); });

  it('errors is non-null', async () => {
    const res = await client.queries.findUserOrErrors({ id: 'user-1' });
    expect(res.errors).not.toBeNull();
  });

  it('data is null', async () => {
    const res = await client.queries.findUserOrErrors({ id: 'user-1' });
    expect(res.data).toBeNull();
  });

  it('first error has correct message', async () => {
    const res = await client.queries.findUserOrErrors({ id: 'user-1' });
    expect(res.errors![0].message).toBe('Not found');
  });
});

// ── getUser — no @glCaptureErrors: throws on error ────────────────────────────

describe('getUser — throws on error response', () => {
  beforeEach(() => { adapter.registerErrors('getUser', [kGraphQLError]); });

  it('throws a GraphLinkError[] when server returns errors', async () => {
    await expect(client.queries.getUser({ id: 'user-1' })).rejects.toSatisfy(
      (e): boolean => Array.isArray(e) && (e as GraphLinkError[])[0]?.message === 'Not found',
    );
  });

  it('thrown value is an array', async () => {
    let thrown: unknown;
    try {
      await client.queries.getUser({ id: 'user-1' });
    } catch (e) {
      thrown = e;
    }
    expect(Array.isArray(thrown)).toBe(true);
  });

  it('first error in thrown array has the correct message', async () => {
    let thrown: unknown;
    try {
      await client.queries.getUser({ id: 'user-1' });
    } catch (e) {
      thrown = e;
    }
    expect((thrown as GraphLinkError[])[0].message).toBe('Not found');
  });
});
