import { afterEach, describe, expect, it } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { DefaultGraphLinkWsAdapter } from '../lib/generated/graphlink.ts';
import { realHttpAdapter, WS_URL } from './real-server-adapter.ts';

type Outcome = { events: number[]; error: unknown };

const adapters: DefaultGraphLinkWsAdapter[] = [];
afterEach(async () => { await Promise.all(adapters.splice(0).map(a => a.close())); });

function clientWith(headers: (() => Promise<Record<string, string> | null>) | undefined): GraphLinkClient {
  const ws = new DefaultGraphLinkWsAdapter(WS_URL, headers);
  adapters.push(ws);
  return new GraphLinkClient(realHttpAdapter, ws);
}

function secureTicks(client: GraphLinkClient, count: number): Promise<Outcome> {
  return new Promise((resolve, reject) => {
    const outcome: Outcome = { events: [], error: undefined };
    const timer = setTimeout(() => reject(new Error('stream never ended')), 8000);
    const finish = () => { clearTimeout(timer); resolve(outcome); };
    client.subscriptions.secureTicks({ count },
      e => { outcome.events.push(e.secureTicks); },
      e => { outcome.error = e; finish(); },
      finish);
  });
}

let nextToken = 0;

describe('connection_init payload', () => {
  it('carries the token to the server', async () => {
    const token = `ts-${Date.now()}-${nextToken++}`;
    const outcome = await secureTicks(clientWith(async () => ({ Authorization: `Bearer ${token}` })), 3);
    expect(outcome.error).toBeUndefined();
    expect(outcome.events).toEqual([1, 2, 3]);
    const starts = await clientWith(undefined).queries.secureTickStarts({ token });
    expect(starts.secureTickStarts).toBe(1);
  });

  it('a subscription without a token fails', async () => {
    const outcome = await secureTicks(clientWith(undefined), 3);
    expect(outcome.events).toEqual([]);
    expect(outcome.error).toBeDefined();
  });
});
