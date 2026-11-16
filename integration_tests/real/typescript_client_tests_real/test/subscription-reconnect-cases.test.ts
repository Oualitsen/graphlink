import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { DefaultGraphLinkWsAdapter } from '../lib/generated/graphlink.ts';
import { httpAdapterForPort, killPort, startServer, wsUrlForPort } from './real-server-adapter.ts';

const RUN_RECONNECT = !!process.env['RUN_RECONNECT_TESTS'];
const port = 9932;
const sleep = (ms: number) => new Promise(res => setTimeout(res, ms));

async function until(what: string, check: () => boolean, timeoutMs = 60_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (!check()) {
    if (Date.now() > deadline) throw new Error(`timed out: ${what}`);
    await sleep(200);
  }
}

class Stream {
  events: string[] = [];
  error: unknown;
  completed = false;
  unsubscribe: () => void;

  constructor(client: GraphLinkClient, label: string, count: number) {
    this.unsubscribe = client.subscriptions.labelTicks(
      { label, count },
      e => { this.events.push(e.labelTicks); },
      e => { this.error = e; },
      () => { this.completed = true; },
    );
  }

  async nextEvent(label: string): Promise<void> {
    const seen = this.events.length;
    await until(`an event for ${label} after the restart`, () => this.events.slice(seen).some(e => e.startsWith(`${label}-`)));
  }
}

describe.skipIf(!RUN_RECONNECT)('reconnect cases', () => {
  let ws: DefaultGraphLinkWsAdapter;
  let client: GraphLinkClient;
  let reconnects = 0;
  const streams: Stream[] = [];

  async function connect(headers?: () => Promise<Record<string, string>>, maxAttempts?: number | null, maxDelay?: number) {
    await startServer(port);
    ws = new DefaultGraphLinkWsAdapter(wsUrlForPort(port), headers, maxAttempts === undefined ? 10 : maxAttempts, maxDelay ?? 30_000);
    client = new GraphLinkClient(httpAdapterForPort(port), ws);
    reconnects = 0;
    (async () => { for await (const _ of ws.onReconnect) { reconnects++; } })();
  }

  const subscribe = (label: string, count = 1000) => {
    const stream = new Stream(client, label, count);
    streams.push(stream);
    return stream;
  };
  const starts = async (label: string) => (await client.queries.labelTickStarts({ label })).labelTickStarts;

  afterEach(async () => {
    streams.splice(0).forEach(s => s.unsubscribe());
    await ws.close();
    killPort(port);
  });

  it('resubscribes with the same variables', async () => {
    await connect();
    const bob = subscribe('bob');
    await until('first event', () => bob.events.length > 0);
    expect(bob.events[0]).toBe('bob-1');

    await startServer(port);
    await until('a reconnect', () => reconnects >= 1);
    await bob.nextEvent('bob');
    expect(await starts('bob')).toBe(1);
  }, 120_000);

  it('does not resubscribe a completed subscription', async () => {
    await connect();
    const done = subscribe('done', 2);
    await until('completion', () => done.completed);
    expect(done.events).toHaveLength(2);

    await startServer(port);
    await sleep(6000);
    expect(await starts('done')).toBe(0);
    expect(done.events).toHaveLength(2);
  }, 120_000);

  it('does not revive a cancelled subscription', async () => {
    await connect();
    const cancelled = subscribe('cancelled');
    await until('first event', () => cancelled.events.length > 0);
    cancelled.unsubscribe();
    await sleep(1000);

    await startServer(port);
    await sleep(6000);
    expect(await starts('cancelled')).toBe(0);
  }, 120_000);

  it('resumes every open subscription on one socket', async () => {
    await connect();
    const a = subscribe('a');
    const b = subscribe('b');
    await until('first events', () => a.events.length > 0 && b.events.length > 0);

    await startServer(port);
    await until('a reconnect', () => reconnects >= 1);
    await a.nextEvent('a');
    await b.nextEvent('b');
    expect(await starts('a')).toBe(1);
    expect(await starts('b')).toBe(1);
  }, 120_000);

  it('a restart during connection_init subscribes once', async () => {
    await connect(async () => ({ 'Ack-Delay': '3000' }));
    const init = subscribe('init');
    await sleep(1000);

    await startServer(port);
    await init.nextEvent('init');
    await sleep(2000);
    expect(await starts('init')).toBe(1);
  }, 120_000);

  it('gives up with a visible error', async () => {
    await connect(undefined, 2, 1000);
    const giveUp = subscribe('giveup');
    await until('first event', () => giveUp.events.length > 0);
    killPort(port);

    await until('an error or an end after the reconnect attempts ran out', () => giveUp.error !== undefined || giveUp.completed);
    expect(giveUp.error).toBeDefined();
  }, 120_000);
});
