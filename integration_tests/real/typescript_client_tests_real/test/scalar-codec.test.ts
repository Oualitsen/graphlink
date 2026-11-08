import { beforeEach, describe, expect, it } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { newClient, newWsAdapter } from './real-server-adapter.ts';

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

describe('a scalar with a codec', () => {
  it('is decoded in a response', async () => {
    expect((await client.queries.scalarFixture()).scalarFixture.opaque).toBe('opaque:o-1');
  });

  it('is encoded in an input field and decoded again', async () => {
    const r = await client.queries.echoScalars({ input: { dt: 'x', long: 1, dts: [], opaque: 'opaque:xyz' } });
    expect(r.echoScalars.opaque).toBe('opaque:xyz');
  });

  it('is encoded in an operation argument and decoded again', async () => {
    const r = await client.queries.echoScalarArgs({ dt: 'x', dts: [], opaque: 'opaque:abc' });
    expect(r.echoScalarArgs.opaque).toBe('opaque:abc');
  });

  it('keeps null as null in both directions', async () => {
    expect((await client.queries.echoScalarArgs({ dt: 'x', dts: [] })).echoScalarArgs.opaque).toBeNull();
    expect((await client.queries.echoScalars({ input: { dt: 'x', long: 1, dts: [] } })).echoScalars.opaque).toBeNull();
  });
});

describe('scalars that are plain aliases', () => {
  it('a JSON scalar keeps its shape', async () => {
    const bag = (await client.queries.scalarFixture()).scalarFixture;
    expect(bag.json).toEqual({ name: 'x', n: 1, list: [1, 'two', false] });
  });

  it('a string-like scalar is passed through', async () => {
    const bag = (await client.queries.scalarFixture()).scalarFixture;
    expect(bag.dt).toBe('2026-01-02T03:04:05Z');
    expect(bag.dts).toEqual(['2026-01-02T03:04:05Z', '2027-02-03T04:05:06Z']);
  });

  it('a Long above 2^53 loses precision, because JSON.parse reads every number as a double', async () => {
    const bag = (await client.queries.scalarFixture()).scalarFixture;
    expect(bag.long).toBe(9007199254740992);
  });
});

function fixtureClient(opaque: unknown): GraphLinkClient {
  const response = JSON.stringify({ data: { scalarFixture: { dt: 'x', long: 1, dts: [], opaque } } });
  return new GraphLinkClient(async () => response, newWsAdapter());
}

describe('a scalar with a codec and a jsonType', () => {
  for (const wire of [7, true, 1.5, { a: 1 }, ['a']]) {
    it(`rejects ${JSON.stringify(wire)} naming the field`, async () => {
      await expect(fixtureClient(wire).queries.scalarFixture()).rejects.toThrow(/opaque/);
    });
  }

  it('runs the template on the right type', async () => {
    expect((await fixtureClient('abc').queries.scalarFixture()).scalarFixture.opaque).toBe('opaque:abc');
  });
});
