import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { createFetchAdapter, createFetchGetAdapter } from '../lib/generated/client/graph-link-adapters.js';
import { DefaultGraphLinkWsAdapter } from '../lib/generated/graphlink.js';
import { UserStatus } from '../lib/generated/enums/user-status.js';
import type { CreateUserInput } from '../lib/generated/inputs/create-user-input.js';

const PORT = 9997;
const GRAPHQL = `http://localhost:${PORT}/graphql`;

const control = async (method: string, path: string): Promise<Record<string, number | boolean>> =>
  (await fetch(`http://localhost:${PORT}/test/apq${path}`, { method })).json() as never;

const stats = () => control('GET', '');

const newClient = () =>
  new GraphLinkClient(
    createFetchAdapter(GRAPHQL),
    createFetchGetAdapter(GRAPHQL),
    new DefaultGraphLinkWsAdapter(`ws://localhost:${PORT}/graphql`),
  );

const newUser: CreateUserInput = {
  name: 'Persisted Pat',
  email: 'pat@test.com',
  status: UserStatus.Active,
  address: { street: 's', city: 'c', country: 'x' },
};

let client: GraphLinkClient;

beforeEach(async () => {
  await control('POST', '/reset');
  client = newClient();
});

describe('a long query', () => {
  it('is registered on the first call: a GET miss, then a POST with the document', async () => {
    const res = await client.queries.persistedLongQuery({ id: 'user-1' });

    expect(res.getUser.name).toBe('Alice Smith');
    expect(await stats()).toMatchObject({ misses: 1, registrations: 1, stored: 1, gets: 1 });
  });

  it('is a single GET hit once registered', async () => {
    await client.queries.persistedLongQuery({ id: 'user-1' });

    const res = await client.queries.persistedLongQuery({ id: 'user-1' });

    expect(res.getUser.name).toBe('Alice Smith');
    expect(await stats()).toMatchObject({ hits: 1, registrations: 1, gets: 2 });
  });

  it('a fresh client reuses what the server already stored', async () => {
    await client.queries.persistedLongQuery({ id: 'user-1' });

    const res = await newClient().queries.persistedLongQuery({ id: 'user-1' });

    expect(res.getUser.name).toBe('Alice Smith');
    expect(await stats()).toMatchObject({ hits: 1, registrations: 1 });
  });

  it('is registered again after the server evicts it', async () => {
    await client.queries.persistedLongQuery({ id: 'user-1' });
    await control('POST', '/evict');

    const res = await client.queries.persistedLongQuery({ id: 'user-1' });

    expect(res.getUser.name).toBe('Alice Smith');
    expect(await stats()).toMatchObject({ registrations: 2, stored: 1 });
  });

  it('still works when the server does not support persisted queries', async () => {
    await control('POST', '/supported/false');

    const first = await client.queries.persistedLongQuery({ id: 'user-1' });
    const second = await client.queries.persistedLongQuery({ id: 'user-1' });

    expect(first.getUser.name).toBe('Alice Smith');
    expect(second.getUser.name).toBe('Alice Smith');
    expect(await stats()).toMatchObject({ stored: 0, gets: 1 });
  });
});

describe('a long mutation', () => {
  it('is registered and sent over POST, never GET', async () => {
    const res = await client.mutations.persistedLongMutation({ input: newUser });

    expect(res.createUser.name).toBe('Persisted Pat');
    expect(await stats()).toMatchObject({ registrations: 1, gets: 0 });
  });

  it('is a hash-only POST once registered', async () => {
    await client.mutations.persistedLongMutation({ input: newUser });

    const res = await client.mutations.persistedLongMutation({ input: newUser });

    expect(res.createUser.email).toBe('pat@test.com');
    expect(await stats()).toMatchObject({ hits: 1, registrations: 1, gets: 0 });
  });
});

it('a short query does not use persisted queries', async () => {
  const res = await client.queries.persistedShortQuery();

  expect(res.listUsers.length).toBeGreaterThan(0);
  expect(await stats()).toMatchObject({ hits: 0, misses: 0, registrations: 0, gets: 0 });
});
