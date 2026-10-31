import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import {
  httpAdapterForPort,
  newWsAdapterForPort,
  newWsAdapterNeverStop,
  killPort,
  startServer,
} from './real-server-adapter.ts';

const RUN_RECONNECT = !!process.env['RUN_RECONNECT_TESTS'];

// ---------------------------------------------------------------------------
// Test 1: subscription resumes after mid-run server halt + restart
// ---------------------------------------------------------------------------
describe.skipIf(!RUN_RECONNECT)('reconnect: server halts during active subscription', () => {
  const port = 9993;
  beforeAll(() => startServer(port), 40_000);
  afterAll(() => killPort(port));

  it('counterTick resumes after server halt', async () => {
    const ws = newWsAdapterForPort(port);
    const client = new GraphLinkClient(httpAdapterForPort(port), ws);
    const stopAt = 5;

    let reconnected = false;
    (async () => { for await (const _ of ws.onReconnect) { reconnected = true; } })();

    const eventSet = new Set<number>();
    let done!: () => void;
    let fail!: (e: unknown) => void;
    const donePromise = new Promise<void>((res, rej) => { done = res; fail = rej; });

    const unsub = client.subscriptions.counterTick(
      async (event) => {
        try {
          const tick = event.counterTick;

          if (tick === stopAt - 1) {
            await startServer(port);
          }

          if (eventSet.has(tick)) {
            done();
            return;
          }
          eventSet.add(tick);
        } catch (e) { fail(e); }
      },
      (e) => console.error('[stream] error:', e),
    );

    try {
      await Promise.race([
        donePromise,
        new Promise<void>((_, rej) => setTimeout(() => rej(new Error('timeout')), 120_000)),
      ]);
      expect(reconnected).toBe(true);
      expect([...eventSet]).toEqual(expect.arrayContaining([1, 2, 3, stopAt - 1]));
    } finally {
      unsub();
      await ws.close();
    }
  }, 120_000);
});

// ---------------------------------------------------------------------------
// Test 2: subscribe before server starts
// ---------------------------------------------------------------------------
describe.skipIf(!RUN_RECONNECT)('reconnect: subscribe before server starts', () => {
  const port = 9995;
  beforeAll(() => killPort(port));
  afterAll(() => killPort(port));

  it('subscription connects once server becomes available', async () => {
    const ws = newWsAdapterForPort(port);
    const client = new GraphLinkClient(httpAdapterForPort(port), ws);

    let reconnected = false;
    (async () => { for await (const _ of ws.onReconnect) { reconnected = true; } })();

    let resolveTick!: (t: number) => void;
    const firstTick = new Promise<number>((res) => { resolveTick = res; });

    const unsub = client.subscriptions.counterTick(
      (event) => { resolveTick(event.counterTick); },
      (e) => console.error('[stream] error:', e),
    );

    // Bring server up — startServer takes ~8 s, so adapter will have failed at
    // least one attempt before it returns.
    await startServer(port);

    try {
      const tick = await Promise.race([
        firstTick,
        new Promise<number>((_, rej) => setTimeout(() => rej(new Error('timeout')), 30_000)),
      ]);
      expect(tick).toBeGreaterThan(0);
      expect(reconnected).toBe(true);
    } finally {
      unsub();
      await ws.close();
    }
  }, 120_000);
});

// ---------------------------------------------------------------------------
// Test 3: maxReconnectAttempts=null — adapter retries indefinitely
// ---------------------------------------------------------------------------
describe.skipIf(!RUN_RECONNECT)('reconnect: null maxReconnectAttempts retries indefinitely', () => {
  const port = 9992;
  const targetAttempts = 10;

  beforeAll(() => killPort(port));
  afterAll(() => killPort(port));

  it(`makes ${targetAttempts} connection attempts without giving up`, async () => {
    // maxReconnectAttempts=null + maxReconnectDelay=2s: caps at ~2 s per attempt.
    // Poll ws.reconnectAttempts until it reaches targetAttempts.
    const ws = newWsAdapterNeverStop(port);
    const client = new GraphLinkClient(httpAdapterForPort(port), ws);

    let reconnected = false;
    (async () => { for await (const _ of ws.onReconnect) { reconnected = true; } })();

    const unsub = client.subscriptions.counterTick(
      () => {},
      (e) => console.error('[stream] error:', e),
    );

    try {
      const deadline = Date.now() + 60_000;
      while (ws.reconnectAttempts < targetAttempts) {
        if (Date.now() > deadline) throw new Error(`Timed out — only reached ${ws.reconnectAttempts}/${targetAttempts}`);
        await new Promise(r => setTimeout(r, 500));
      }
      expect(ws.reconnectAttempts).toBeGreaterThanOrEqual(targetAttempts);
      expect(reconnected).toBe(false);
    } finally {
      unsub();
      await ws.close();
    }
  }, 120_000);
});
