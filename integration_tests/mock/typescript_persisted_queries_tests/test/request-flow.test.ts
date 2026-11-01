import { describe, it, expect, beforeEach } from 'vitest';
import { GraphLinkSha256 } from '../lib/generated/client/graph-link-sha256.js';
import { kUserAliceJson, kPostJson } from '../../typescript_client_tests/test/fixtures.ts';
import { ApqServer } from './apq-server.ts';
import { newClient, hashOf, createUserInput } from './helpers.ts';

let server: ApqServer;
let client: ReturnType<typeof newClient>;

beforeEach(() => {
  server = new ApqServer();
  client = newClient(server);
});

describe('a long query', () => {
  beforeEach(() => server.respondTo('persistedLongQuery', { getUser: kUserAliceJson }));

  it('is sent as a hash first and registered by the retry', async () => {
    const res = await client.queries.persistedLongQuery({ id: 'user-1' });

    expect(res.getUser.name).toBe('Alice Smith');
    expect(server.requests).toHaveLength(2);
    expect(server.requests[0]).not.toHaveProperty('query');
    expect(server.requests[0].operationName).toBe('persistedLongQuery');
    expect(server.requests[0].variables).toEqual({ id: 'user-1' });
    expect(typeof server.requests[1].query).toBe('string');
    expect(server.requests[1].variables).toEqual({ id: 'user-1' });
  });

  it('the hash is the SHA-256 of the query that the retry carries', async () => {
    await client.queries.persistedLongQuery({ id: 'user-1' });

    const retry = server.requests[1];
    expect(hashOf(retry)).toEqual({ version: 1, sha256Hash: GraphLinkSha256.hex(retry.query as string) });
    expect(hashOf(server.requests[0])).toEqual(hashOf(retry));
  });

  it('is a single request once the server knows it', async () => {
    await client.queries.persistedLongQuery({ id: 'user-1' });
    server.requests.length = 0;

    await client.queries.persistedLongQuery({ id: 'user-2' });

    expect(server.requests).toHaveLength(1);
    expect(server.isHashOnly(server.requests[0])).toBe(true);
    expect(server.requests[0].variables).toEqual({ id: 'user-2' });
  });

  it('is registered again after the server evicts it', async () => {
    await client.queries.persistedLongQuery({ id: 'user-1' });
    server.evict();
    server.requests.length = 0;

    const res = await client.queries.persistedLongQuery({ id: 'user-1' });

    expect(res.getUser.name).toBe('Alice Smith');
    expect(server.requests).toHaveLength(2);
    expect(server.isHashOnly(server.requests[0])).toBe(true);
    expect(server.requests[1]).toHaveProperty('query');
  });
});

describe('a server that reports a missing hash only by its code', () => {
  it('still gets the retry with the query', async () => {
    server.notFoundMessage = 'Unknown query';
    server.respondTo('persistedLongQuery', { getUser: kUserAliceJson });

    const res = await client.queries.persistedLongQuery({ id: 'user-1' });

    expect(res.getUser.name).toBe('Alice Smith');
    expect(server.requests).toHaveLength(2);
    expect(server.requests[1]).toHaveProperty('query');
  });
});

describe('a short query', () => {
  it('is sent in full, with no hash', async () => {
    server.respondTo('persistedShortQuery', { listUsers: [] });

    await client.queries.persistedShortQuery();

    expect(server.requests).toHaveLength(1);
    expect(server.requests[0].query).toContain('listUsers');
    expect(server.requests[0]).not.toHaveProperty('extensions');
  });
});

describe('a long mutation', () => {
  it('uses the same hash-then-register flow', async () => {
    server.respondTo('persistedLongMutation', { createUser: kUserAliceJson });

    const res = await client.mutations.persistedLongMutation({ input: createUserInput });

    expect(res.createUser.name).toBe('Alice Smith');
    expect(server.requests).toHaveLength(2);
    expect(server.isHashOnly(server.requests[0])).toBe(true);
    expect(server.requests[1]).toHaveProperty('query');
  });
});

describe('a server without APQ', () => {
  beforeEach(() => {
    server.supported = false;
    server.respondTo('persistedLongQuery', { getUser: kUserAliceJson });
  });

  it('gets the full query right after the first refusal', async () => {
    const res = await client.queries.persistedLongQuery({ id: 'user-1' });

    expect(res.getUser.name).toBe('Alice Smith');
    expect(server.requests).toHaveLength(2);
    expect(server.requests[1]).toHaveProperty('query');
    expect(server.requests[1]).not.toHaveProperty('extensions');
  });

  it('is not asked about hashes again', async () => {
    await client.queries.persistedLongQuery({ id: 'user-1' });
    server.requests.length = 0;

    await client.queries.persistedLongQuery({ id: 'user-2' });

    expect(server.requests).toHaveLength(1);
    expect(server.requests[0]).toHaveProperty('query');
    expect(server.requests[0]).not.toHaveProperty('extensions');
  });
});

describe('errors that are not a missing persisted query', () => {
  it('a GraphQL error is returned as is, without a second request', async () => {
    server.respondTo('persistedLongQuery', { getUser: kUserAliceJson });
    await client.queries.persistedLongQuery({ id: 'user-1' });
    server.requests.length = 0;
    server.respondWithErrors('persistedLongQuery', [{ message: 'boom' }]);

    await expect(client.queries.persistedLongQuery({ id: 'user-1' })).rejects.toBeDefined();
    expect(server.requests).toHaveLength(1);
  });

  it('a transport failure propagates, without a second request', async () => {
    server.respondTo('persistedLongMutation', { createUser: kUserAliceJson });
    server.failWith = new Error('timeout');

    await expect(client.mutations.persistedLongMutation({ input: createUserInput })).rejects.toThrow('timeout');
    expect(server.methods).toEqual(['POST']);
  });
});

describe('a cached query', () => {
  it('hashes the assembled request, not its pieces', async () => {
    server.respondTo('fetchCachedPair', { user: kUserAliceJson, post: kPostJson });

    const res = await client.queries.fetchCachedPair({ userId: 'user-1', postId: 'post-1' });

    expect(res.user.name).toBe('Alice Smith');
    expect(server.requests).toHaveLength(2);
    const retry = server.requests[1];
    expect(hashOf(retry).sha256Hash).toBe(GraphLinkSha256.hex(retry.query as string));
    expect(retry.query).toContain('getCachedUser');
  });
});
