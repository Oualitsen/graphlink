import { readFileSync } from 'node:fs';
import { beforeEach, describe, expect, it } from 'vitest';
import { RestError, type GraphLinkClient, type GraphLinkError } from '../lib/generated/graphlink';
import { newClient } from './support';
import { variant } from './variant';

interface FaultCase {
  fault: string;
  ops: string;
  expect: 'value' | 'failure' | 'either';
}

const faultUrl = `http://127.0.0.1:${variant.faultPort}`;
const cases: FaultCase[] = JSON.parse(readFileSync('../fault_server/cases.json', 'utf8'));

const knownDefects: Record<string, string> = {
};

const opNames: Record<string, string> = { g: 'GraphQL getCount', c: 'REST count', p: 'REST status' };

const post = (path: string) => fetch(`${faultUrl}${path}`, { method: 'POST' });

let client: GraphLinkClient;

beforeEach(async () => {
  await post('/_reset');
  client = newClient({ baseUrl: faultUrl });
});

const calls: Record<string, () => Promise<unknown>> = {
  g: () => client.queries.getCount(),
  c: () => client.queries.count(),
  p: () => client.queries.status({ code: 200 }),
};

const healthy: Record<string, () => Promise<void>> = {
  g: async () => expect((await client.queries.getCount()).getCount).toBe(19),
  c: async () => expect(await client.queries.count()).toBe(7),
  p: async () => expect((await client.queries.status({ code: 200 }))!.name).toBe('Pen'),
};

describe('fault injection', () => {
  for (const c of cases) {
    for (const op of c.ops) {
      const run = knownDefects[`${c.fault}:${op}`] === undefined ? it : it.skip;
      run(`${c.fault}: ${opNames[op]} -> ${c.expect}, then the client still works`, async () => {
        await post(`/_arm?fault=${c.fault}`);
        let result: unknown;
        let error: unknown;
        try {
          result = await Promise.race([
            calls[op](),
            new Promise((_, reject) => setTimeout(() => reject(new Error(`${c.fault} hung for 8 seconds`)), 8000)),
          ]);
        } catch (e) {
          if (e instanceof Error && e.message.endsWith('hung for 8 seconds')) throw e;
          error = e;
        }
        if (c.expect === 'value') expect(error, `unexpected failure: ${String(error)}`).toBeUndefined();
        if (c.expect === 'failure') expect(error, `decoded without a failure: ${JSON.stringify(result)}`).toBeDefined();
        await healthy[op]();
      }, 15000);
    }
  }

  it('a RestError carries the status and the body of a gateway page', async () => {
    await post('/_arm?fault=html-502');
    const failure = await client.queries.count().catch((e: unknown) => e);
    expect(failure).toBeInstanceOf(RestError);
    expect((failure as RestError).status).toBe(502);
    expect((failure as RestError).body).toContain('Bad Gateway');
  });

  it('a GraphQL error response reaches the caller with its message, path and extensions', async () => {
    await post('/_arm?fault=gql-errors-only');
    const failure = (await client.queries.getCount().catch((e: unknown) => e)) as GraphLinkError[];
    expect(failure).toHaveLength(1);
    expect(failure[0].message).toBe('boom');
    expect(failure[0].path).toEqual(['getCount']);
    expect(failure[0].extensions).toEqual({ code: 'BAD' });
  });

  for (const [fault, status, text] of [['html-502', 502, 'Bad Gateway'], ['status-401-json', 401, 'unauthorized']] as const) {
    it(`a GraphQL call keeps the HTTP status and body of ${fault}`, async () => {
      await post(`/_arm?fault=${fault}`);
      const failure = (await client.queries.getCount().catch((e: unknown) => e)) as GraphLinkError[];
      expect(failure).toHaveLength(1);
      expect(failure[0].status).toBe(status);
      expect(failure[0].body).toContain(text);
    });
  }

  it('a response without data and without errors says so', async () => {
    await post('/_arm?fault=gql-empty-object');
    const failure = (await client.queries.getCount().catch((e: unknown) => e)) as GraphLinkError[];
    expect(failure[0].message).toContain('no data');
  });
});

describe('a call that the caller gives up on', () => {
  const call = (c: GraphLinkClient, op: string): Promise<unknown> => {
    if (op === 'g') return c.queries.getCount();
    if (op === 'c') return c.queries.count();
    if (op === 'k') return c.queries.cachedStatus({ code: 200 });
    return c.queries.status({ code: 200 });
  };

  for (const op of 'gcpk') {
    it(`${op}: the timeout fires promptly and the client still works`, async () => {
      await post('/_reset');
      const fresh = newClient({ baseUrl: faultUrl });
      await post('/_arm?fault=slow');
      const started = Date.now();
      const giveUp = new Promise((_, reject) => setTimeout(() => reject(new Error('gave up')), 200));
      await expect(Promise.race([call(fresh, op), giveUp])).rejects.toThrow('gave up');
      expect(Date.now() - started).toBeLessThan(700);
      await call(fresh, op);
    }, 15000);
  }
});
