import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { createServer, type Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { createFetchAdapter, createFetchGetAdapter } from '../lib/generated/client/graph-link-adapters.js';
import { GraphLinkGetNotSupported } from '../lib/generated/client/graph-link-persisted-queries.js';
import { kUserAliceJson } from '../../../../mock/typescript_client_tests/test/fixtures.ts';
import { MockWsAdapter } from '../../../../mock/typescript_client_tests/test/mock-adapter.ts';
import { ApqServer } from './apq-server.ts';

interface Seen { method: string; query: URLSearchParams; authorization: string | undefined }

let http: Server;
let server: ApqServer;
let client: GraphLinkClient;
let seen: Seen[];

beforeEach(async () => {
  server = new ApqServer();
  server.respondTo('persistedLongQuery', { getUser: kUserAliceJson });
  seen = [];
  http = createServer(async (req, res) => {
    const url = new URL(req.url!, 'http://localhost');
    seen.push({ method: req.method!, query: url.searchParams, authorization: req.headers.authorization });
    try {
      let body: string;
      if (req.method === 'GET') {
        const p = url.searchParams;
        body = await server.get(JSON.stringify({
          ...(p.has('operationName') ? { operationName: p.get('operationName') } : {}),
          variables: p.has('variables') ? JSON.parse(p.get('variables')!) : {},
          extensions: JSON.parse(p.get('extensions')!),
        }));
      } else {
        const chunks: Buffer[] = [];
        for await (const chunk of req) chunks.push(chunk as Buffer);
        body = await server.call(Buffer.concat(chunks).toString('utf8'));
      }
      res.setHeader('Content-Type', 'application/json');
      res.end(body);
    } catch (e) {
      if (e instanceof GraphLinkGetNotSupported) {
        res.statusCode = 405;
        res.end();
        return;
      }
      throw e;
    }
  });
  await new Promise<void>(resolve => http.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${(http.address() as AddressInfo).port}/graphql`;
  const headers = async () => ({ authorization: 'Bearer token' });
  client = new GraphLinkClient(
    createFetchAdapter(url, { headers }),
    createFetchGetAdapter(url, { headers }),
    new MockWsAdapter() as never,
  );
});

afterEach(() => new Promise<void>(resolve => { http.closeAllConnections(); http.close(() => resolve()); }));

describe('the fetch adapters', () => {
  it('a cold long query is a GET with the hash, then a POST with the query', async () => {
    const res = await client.queries.persistedLongQuery({ id: 'user-1' });

    expect(res.getUser.name).toBe('Alice Smith');
    expect(seen.map(r => r.method)).toEqual(['GET', 'POST']);
  });

  it('the GET carries the operation, its variables and the hash in the URL', async () => {
    await client.queries.persistedLongQuery({ id: 'user-1' });

    const query = seen[0].query;
    expect([...query.keys()].sort()).toEqual(['extensions', 'operationName', 'variables']);
    expect(query.get('operationName')).toBe('persistedLongQuery');
    expect(JSON.parse(query.get('variables')!)).toEqual({ id: 'user-1' });
    expect(JSON.parse(query.get('extensions')!).persistedQuery.version).toBe(1);
  });

  it('a warm query is a single GET', async () => {
    await client.queries.persistedLongQuery({ id: 'user-1' });
    seen.length = 0;

    await client.queries.persistedLongQuery({ id: 'user-2' });

    expect(seen.map(r => r.method)).toEqual(['GET']);
  });

  it('the headers provider applies to the GET as well', async () => {
    await client.queries.persistedLongQuery({ id: 'user-1' });

    expect(seen[0].authorization).toBe('Bearer token');
  });

  it('a 405 on GET sends the same request as a POST and remembers it', async () => {
    server.getSupported = false;

    const res = await client.queries.persistedLongQuery({ id: 'user-1' });

    expect(res.getUser.name).toBe('Alice Smith');
    expect(seen.map(r => r.method)).toEqual(['GET', 'POST', 'POST']);
    seen.length = 0;

    await client.queries.persistedLongQuery({ id: 'user-2' });
    expect(seen.map(r => r.method)).toEqual(['POST']);
  });
});
