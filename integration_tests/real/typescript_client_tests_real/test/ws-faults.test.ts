import { readFileSync } from 'node:fs';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { DefaultGraphLinkWsAdapter } from '../lib/generated/graphlink.ts';

const FAULT_PORT = Number(process.env['WS_FAULT_PORT'] ?? 9943);
const FAULT_URL = `http://127.0.0.1:${FAULT_PORT}`;

interface WsCase {
  fault: string;
  expect: 'value' | 'error' | 'settles';
  message?: string;
  times?: number;
  waitSeconds?: number;
  noSubscribeBeforeAck?: boolean;
  pong?: boolean;
  maxConnections?: number;
  minConnections?: number;
}

const CASES: WsCase[] = JSON.parse(readFileSync(new URL('../../fault_server/ws_cases.json', import.meta.url), 'utf8'));

const KNOWN_DEFECTS: Record<string, string> = {};

const sleep = (ms: number) => new Promise(res => setTimeout(res, ms));

async function connections(): Promise<{ frames: { type: string }[] }[]> {
  return (await fetch(`${FAULT_URL}/_ws_log`)).json();
}

describe('websocket faults', () => {
  let ws: DefaultGraphLinkWsAdapter;
  let unsubscribe: (() => void) | undefined;

  beforeEach(async () => {
    await fetch(`${FAULT_URL}/_reset`, { method: 'POST' });
    ws = new DefaultGraphLinkWsAdapter(`ws://127.0.0.1:${FAULT_PORT}/graphql`);
  });

  afterEach(async () => {
    unsubscribe?.();
    await ws.close();
  });

  for (const c of CASES) {
    const run = KNOWN_DEFECTS[c.fault] ? it.skip : it;
    run(`${c.fault}${KNOWN_DEFECTS[c.fault] ? ` (${KNOWN_DEFECTS[c.fault]})` : ''}`, async () => {
      await fetch(`${FAULT_URL}/_arm?fault=${c.fault}&times=${c.times ?? 1}`, { method: 'POST' });
      const client = new GraphLinkClient(async () => '{}', ws);
      const events: number[] = [];
      let error: unknown;
      let settled = false;
      unsubscribe = client.subscriptions.counterTick(
        e => { events.push(e.counterTick); },
        e => { error = e; settled = true; },
        () => { settled = true; },
      );
      const deadline = Date.now() + (c.waitSeconds ?? 8) * 1000;
      while (!settled && Date.now() < deadline) await sleep(100);
      const log = await connections();

      if (c.waitSeconds === undefined) {
        expect(settled, 'the subscription hung').toBe(true);
        if (c.expect === 'value') {
          expect(error).toBeUndefined();
          expect(events).toEqual([1]);
        } else if (c.expect === 'error') {
          expect(error, `no failure, events=${events}`).toBeDefined();
          if (c.message) expect(error instanceof Error ? error.message : JSON.stringify(error)).toContain(c.message);
        }
      }
      const sent = log.flatMap(l => l.frames.map(f => f.type));
      if (c.noSubscribeBeforeAck) expect(sent).not.toContain('subscribe');
      if (c.pong) expect(sent).toContain('pong');
      if (c.maxConnections !== undefined) expect(log.length).toBeLessThanOrEqual(c.maxConnections);
      if (c.minConnections !== undefined) expect(log.length).toBeGreaterThanOrEqual(c.minConnections);
    }, 30_000);
  }
});
