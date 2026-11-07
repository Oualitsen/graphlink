import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { OnlyOne, Spelling } from '../lib/generated/graphlink.js';
import { DefaultGraphLinkWsAdapter } from '../lib/generated/graphlink.ts';
import { realHttpAdapter, WS_URL } from './real-server-adapter.ts';

type Outcome<T> = { events: T[]; completed: boolean; error: unknown };

let wsAdapter: DefaultGraphLinkWsAdapter;
let client: GraphLinkClient;
beforeEach(() => {
  wsAdapter = new DefaultGraphLinkWsAdapter(WS_URL);
  client = new GraphLinkClient(realHttpAdapter, wsAdapter);
});
afterEach(async () => { await wsAdapter.close(); });

function run<T>(
  subscribe: (
    onEvent: (e: T) => void,
    onError: (e: unknown) => void,
    onComplete: () => void,
  ) => () => void,
  timeoutMs = 8000,
): Promise<Outcome<T>> {
  return new Promise((resolve, reject) => {
    const outcome: Outcome<T> = { events: [], completed: false, error: undefined };
    const timer = setTimeout(() => reject(new Error(`stream never ended: ${outcome.events.length} events`)), timeoutMs);
    const finish = () => { clearTimeout(timer); resolve(outcome); };
    subscribe(
      e => { outcome.events.push(e); },
      e => { outcome.error = e; finish(); },
      () => { outcome.completed = true; finish(); },
    );
  });
}

describe('subscription arguments of every shape', () => {
  it('lists, nested lists, nulls and enums round trip', async () => {
    const { events, completed } = await run((ev, er, co) => client.subscriptions.subEchoArgs({
      a: [1, 2], b: [1, null], c: [[1], [], [2, 3]],
      e: [Spelling.XY, Spelling.Http2Ok], f: [null, Spelling.V1],
    }, ev, er, co));
    expect(completed).toBe(true);
    expect(events).toHaveLength(1);
    const r = events[0].subEchoArgs;
    expect(r.a).toEqual([1, 2]);
    expect(r.b).toEqual([1, null]);
    expect(r.c).toEqual([[1], [], [2, 3]]);
    expect(r.e).toEqual([Spelling.XY, Spelling.Http2Ok]);
    expect(r.f).toEqual([null, Spelling.V1]);
  });

  it('omitted arguments are null and declared defaults apply', async () => {
    const { events } = await run((ev, er, co) => client.subscriptions.subEchoArgs({ a: [], e: [] }, ev, er, co));
    const r = events[0].subEchoArgs;
    expect(r.b).toBeNull();
    expect(r.c).toBeNull();
    expect(r.f).toBeNull();
    expect(r.g).toEqual([Spelling.A, Spelling.B2]);
    expect(r.one).toBe(OnlyOne.Only);
  });

  it('an input object with list and enum members round trips', async () => {
    const { events } = await run((ev, er, co) => client.subscriptions.subEchoInput({
      input: { a: [3, 4], b: [null, 5], c: [[1, 2], []], e: [Spelling.SnakeCase2], f: [Spelling.A, null], g: [Spelling.V1] },
    }, ev, er, co));
    const r = events[0].subEchoInput;
    expect(r.a).toEqual([3, 4]);
    expect(r.b).toEqual([null, 5]);
    expect(r.c).toEqual([[1, 2], []]);
    expect(r.e).toEqual([Spelling.SnakeCase2]);
    expect(r.f).toEqual([Spelling.A, null]);
    expect(r.g).toEqual([Spelling.V1]);
  });
});

describe('server-side completion', () => {
  it('delivers every event and then completes', async () => {
    const o = await run((ev, er, co) => client.subscriptions.finiteTicks({ count: 5 }, ev, er, co));
    expect(o.events.map(e => e.finiteTicks)).toEqual([1, 2, 3, 4, 5]);
    expect(o.completed).toBe(true);
    expect(o.error).toBeUndefined();
  });

  it('completes without events when the server has none', async () => {
    const o = await run((ev, er, co) => client.subscriptions.finiteTicks({ count: 0 }, ev, er, co));
    expect(o.events).toEqual([]);
    expect(o.completed).toBe(true);
  });
});

describe('error mid-stream', () => {
  it('events before the failure arrive, then the error and no completion', async () => {
    const o = await run((ev, er, co) => client.subscriptions.flakyTicks({ failAfter: 3 }, ev, er, co));
    expect(o.events.map(e => e.flakyTicks)).toEqual([1, 2, 3]);
    expect(o.error).toBeDefined();
    expect(o.completed).toBe(false);
  });

  it('a failure before the first event surfaces as an error', async () => {
    const o = await run((ev, er, co) => client.subscriptions.flakyTicks({ failAfter: 0 }, ev, er, co));
    expect(o.events).toEqual([]);
    expect(o.error).toBeDefined();
  });

  it('a failed stream does not break the next subscription', async () => {
    await run((ev, er, co) => client.subscriptions.flakyTicks({ failAfter: 1 }, ev, er, co));
    const o = await run((ev, er, co) => client.subscriptions.finiteTicks({ count: 2 }, ev, er, co));
    expect(o.events).toHaveLength(2);
    expect(o.completed).toBe(true);
  });
});
