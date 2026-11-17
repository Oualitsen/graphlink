import { beforeEach, describe, expect, it } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { defaultEverythingInput } from '../lib/generated/graphlink.js';
import { newClient } from './real-server-adapter.ts';

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

const echo = async (input: object) =>
  (await client.queries.echoEverything({ input: { ...defaultEverythingInput, ...input } })).echoEverything;

describe('extreme variable values', () => {
  it('Int at both 32-bit limits', async () => {
    const r = await echo({ i: 2147483647, neg: -2147483648 });
    expect(r.i).toBe(2147483647);
    expect(r.neg).toBe(-2147483648);
  });

  it('Float at 1e308 and negative zero', async () => {
    const r = await echo({ f: 1e308, exp: -0 });
    expect(r.f).toBe(1e308);
    // JSON.stringify(-0) is "0", so the sign never leaves the client: the other languages echo -0.0.
    expect(Object.is(r.exp, 0)).toBe(true);
  });

  it('a string with a NUL character', async () => {
    expect((await echo({ s: 'a\u0000b' })).s).toBe('a\u0000b');
  });

  it('a string with lone surrogates', async () => {
    const sent = 'x\ud800y\udc00z';
    expect((await echo({ s: sent })).s).toBe(sent);
  });
});
