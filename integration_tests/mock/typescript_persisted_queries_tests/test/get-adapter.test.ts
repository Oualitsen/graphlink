import { describe, it, expect, beforeEach } from 'vitest';
import { kUserAliceJson } from '../../typescript_client_tests/test/fixtures.ts';
import { ApqServer } from './apq-server.ts';
import { newClient, createUserInput } from './helpers.ts';

let server: ApqServer;
let client: ReturnType<typeof newClient>;

beforeEach(() => {
  server = new ApqServer();
  client = newClient(server);
  server.respondTo('persistedLongQuery', { getUser: kUserAliceJson });
  server.respondTo('persistedShortQuery', { listUsers: [] });
  server.respondTo('persistedLongMutation', { createUser: kUserAliceJson });
});

describe('a long query', () => {
  it('asks with a GET first and registers with a POST', async () => {
    await client.queries.persistedLongQuery({ id: 'user-1' });

    expect(server.methods).toEqual(['GET', 'POST']);
    expect(server.isHashOnly(server.requests[0])).toBe(true);
    expect(server.requests[1]).toHaveProperty('query');
  });

  it('is a single GET once the server knows it', async () => {
    await client.queries.persistedLongQuery({ id: 'user-1' });
    server.methods.length = 0;

    await client.queries.persistedLongQuery({ id: 'user-2' });

    expect(server.methods).toEqual(['GET']);
  });

  it('hands the GET adapter the hash-only payload, with no query', async () => {
    await client.queries.persistedLongQuery({ id: 'user-1' });

    expect(Object.keys(server.requests[0]).sort()).toEqual(['extensions', 'operationName', 'variables']);
  });
});

describe('requests that never use GET', () => {
  it('a short query is a plain POST', async () => {
    await client.queries.persistedShortQuery();

    expect(server.methods).toEqual(['POST']);
  });

  it('a mutation sends its hash over POST', async () => {
    await client.mutations.persistedLongMutation({ input: createUserInput });

    expect(server.methods).toEqual(['POST', 'POST']);
    expect(server.isHashOnly(server.requests[0])).toBe(true);
  });
});

describe('a server that refuses GET', () => {
  beforeEach(() => { server.getSupported = false; });

  it('gets the same hash-only request as a POST', async () => {
    const res = await client.queries.persistedLongQuery({ id: 'user-1' });

    expect(res.getUser.name).toBe('Alice Smith');
    expect(server.methods).toEqual(['GET', 'POST', 'POST']);
    expect(server.requests).toHaveLength(2);
    expect(server.isHashOnly(server.requests[0])).toBe(true);
    expect(server.requests[1]).toHaveProperty('query');
  });

  it('is not asked with a GET again', async () => {
    await client.queries.persistedLongQuery({ id: 'user-1' });
    server.methods.length = 0;

    await client.queries.persistedLongQuery({ id: 'user-2' });

    expect(server.methods).toEqual(['POST']);
  });
});

describe('a server without APQ', () => {
  it('answers the GET with a refusal, then gets the full query by POST', async () => {
    server.supported = false;

    await client.queries.persistedLongQuery({ id: 'user-1' });

    expect(server.methods).toEqual(['GET', 'POST']);
    expect(server.requests[1]).toHaveProperty('query');
    expect(server.requests[1]).not.toHaveProperty('extensions');
  });
});

describe('other GET failures', () => {
  it('propagate untouched, with no POST', async () => {
    server.getFailWith = new Error('network down');

    await expect(client.queries.persistedLongQuery({ id: 'user-1' })).rejects.toThrow('network down');
    expect(server.methods).toEqual(['GET']);
  });
});
