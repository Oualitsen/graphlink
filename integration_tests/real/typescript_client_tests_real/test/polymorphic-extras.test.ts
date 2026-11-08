import { beforeEach, describe, expect, it } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import type { Span, Stamp, Video } from '../lib/generated/graphlink.js';
import { DefaultGraphLinkWsAdapter, UserStatus } from '../lib/generated/graphlink.ts';
import { newClient, realHttpAdapter, WS_URL } from './real-server-adapter.ts';

type Json = Record<string, any>;

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

const kinds = (values: ReadonlyArray<{ __typename: string } | null | undefined>) => values.map((v) => v?.__typename ?? null);

function collect<T>(n: number, subscribe: (onData: (e: T) => void, onError: (e: unknown) => void) => () => void): Promise<T[]> {
  return new Promise((resolve, reject) => {
    const events: T[] = [];
    const timer = setTimeout(() => reject(new Error(`timeout: got ${events.length}/${n} events`)), 10000);
    subscribe(
      (e) => { events.push(e); if (events.length >= n) { clearTimeout(timer); resolve(events); } },
      (err) => { clearTimeout(timer); reject(err); },
    );
  });
}

describe('nested lists of polymorphic types', () => {
  it('lists of lists of unions and interfaces', async () => {
    const grid = (await client.queries.grid({})).grid;
    expect(grid.cells.map((row) => kinds(row as any))).toEqual([['Photo', null], ['Video'], []]);
    expect(grid.rows.map((row) => kinds(row))).toEqual([['Article', 'Comment'], ['Article']]);
    expect(kinds(grid.maybe![0] as any)).toEqual(['Photo', 'Document']);
  });

  it('empty and null lists stay as they are', async () => {
    const grid = (await client.queries.grid({ empty: true })).grid;
    expect(grid.cells).toEqual([]);
    expect(grid.rows).toEqual([]);
    expect(grid.maybe).toBeNull();
  });

  it('a projected selection of nested lists', async () => {
    const grid = (await client.queries.gridProjected({})).grid as Json;
    expect(grid.cells[0][0].width).toBe(640);
    expect(grid.cells[0][1]).toBeNull();
    expect(grid.cells[1][0].seconds).toBe(30);
    expect(grid.cells[2]).toEqual([]);
    expect(grid.rows[0].map((e: Json) => e.id)).toEqual(['a1', 'c1']);
    expect(grid.rows[0][0].title).toBe('Hello');
    expect(grid.rows[0][1].text).toBe('Nice');
    expect(grid.maybe[0][0].url).toBe('http://cdn/1.png');
    expect(grid.maybe[0][1].id).toBe('d1');
  });
});

describe('custom scalars inside polymorphic types', () => {
  it('a list of a union with scalar fields', async () => {
    const moments = (await client.queries.moments()).moments;
    const stamp = moments[0] as Stamp;
    expect(stamp.at).toBe('2026-01-02T03:04:05Z');
    expect(stamp.big).toBe(4294967296);
    const span = moments[1] as Span;
    expect(span.until).toBe('2026-02-04');
    expect(span.opaque).toBe('opaque:o-9');
    expect(span.dts).toEqual(['2026-03-04T05:06:07Z']);
  });

  it('a list of an interface with scalar fields', async () => {
    const timed = (await client.queries.timed()).timed;
    expect(kinds(timed)).toEqual(['Span', 'Stamp']);
    expect((timed[0] as Span).opaque).toBe('opaque:o-9');
    expect((timed[1] as Stamp).big).toBe(4294967296);
  });

  it('a projected union keeps the scalars it selects', async () => {
    const moments = (await client.queries.momentsProjected()).moments as Json[];
    expect(moments[0].at).toBe('2026-01-02T03:04:05Z');
    expect(moments[0].big).toBe(4294967296);
    expect(moments[1].opaque).toBe('opaque:o-9');
    expect(moments[1].until).toBe('2026-02-04');
  });

  it('an interface selection shares the interface scalar', async () => {
    const timed = (await client.queries.timedProjected()).timed as Json[];
    expect(timed.map((t) => t.at)).toEqual(['2026-02-03T04:05:06Z', '2026-01-02T03:04:05Z']);
    expect(timed[0].opaque).toBe('opaque:o-9');
    expect(timed[1].big).toBe(4294967296);
  });
});

describe('a union member that points back at its union', () => {
  it('three levels deep', async () => {
    const chain = (await client.queries.chainDeep({ id: 'l1' })).chain as Json;
    expect(chain.id).toBe('l1');
    expect(chain.next.id).toBe('l2');
    expect(chain.next.next.id).toBe('e1');
    expect(chain.next.next.reason).toBe('done');
  });

  it('the end of the chain directly, and an unknown id', async () => {
    expect(((await client.queries.chainDeep({ id: 'e1' })).chain as Json).reason).toBe('done');
    expect((await client.queries.chainDeep({ id: 'nope' })).chain).toBeNull();
  });

  it('the generated all-fields selection stops after one level', async () => {
    const chain = (await client.queries.chain({ id: 'l1' })).chain as Json;
    expect(chain.id).toBe('l1');
    expect(chain.next.id).toBe('l2');
  });
});

describe('lists of unions and interfaces in every operation kind', () => {
  const cachedSeconds = async () => ((await client.queries.cachedAttachments()).cachedAttachments[1] as Video).seconds;

  it('a cached list is served once and fetched again after its tag is evicted', async () => {
    expect(kinds((await client.queries.cachedAttachments()).cachedAttachments)).toEqual(['Photo', 'Video', 'Document']);
    const before = await cachedSeconds();
    expect(await cachedSeconds()).toBe(before);
    await client.mutations.evictAttachments();
    expect(await cachedSeconds()).not.toBe(before);
  });

  it('an error on a list of unions throws and a good call still works', async () => {
    await expect(client.queries.failingAttachments({ fail: true })).rejects.toBeTruthy();
    expect((await client.queries.failingAttachments({ fail: false })).failingAttachments).toHaveLength(3);
  });

  it('a mutation returning a list of unions', async () => {
    expect(kinds((await client.mutations.bulkAttachments({ n: 5 })).bulkAttachments)).toEqual(['Photo', 'Video', 'Document', 'Photo', 'Video']);
    expect((await client.mutations.bulkAttachments({ n: 0 })).bulkAttachments).toEqual([]);
  });

  it('a mutation returning a list of an interface', async () => {
    expect(kinds((await client.mutations.bulkEntities()).bulkEntities)).toEqual(['Article', 'Comment', 'Article']);
  });

  it('a subscription emitting lists of unions', async () => {
    const ws = new DefaultGraphLinkWsAdapter(WS_URL);
    try {
      const sub = new GraphLinkClient(realHttpAdapter, ws);
      const batches = await collect<Json>(2, (onData, onErr) => sub.subscriptions.attachmentsBatch(onData, onErr));
      expect(kinds(batches[0].attachmentsBatch)).toEqual(['Photo', 'Video', 'Document']);
      expect(kinds(batches[1].attachmentsBatch)).toEqual(['Document']);
    } finally {
      await ws.close();
    }
  }, 15000);

  it('a subscription emitting a list of an interface', async () => {
    const ws = new DefaultGraphLinkWsAdapter(WS_URL);
    try {
      const sub = new GraphLinkClient(realHttpAdapter, ws);
      const [batch] = await collect<Json>(1, (onData, onErr) => sub.subscriptions.entityBatch(onData, onErr));
      expect(kinds(batch.entityBatch)).toEqual(['Article', 'Comment']);
    } finally {
      await ws.close();
    }
  }, 15000);
});

describe('@oneOf inputs with richer members', () => {
  const pick = async (p: Json) => (await client.queries.describePick({ pick: p as any })).describePick;

  it('an input object', async () => {
    expect(await pick({ inner: { n: 5, label: 'x', tags: ['t'] } })).toBe('{inner={label=x, n=5, tags=[t]}}');
  });

  it('an enum', async () => {
    expect(await pick({ status: UserStatus.Suspended })).toBe('{status=SUSPENDED}');
  });

  it('a list, including an empty one', async () => {
    expect(await pick({ ids: [1, 2] })).toBe('{ids=[1, 2]}');
    expect(await pick({ ids: [] })).toBe('{ids=[]}');
  });

  it('another oneOf input', async () => {
    expect(await pick({ pet: { cat: 'Tom' } })).toBe('{pet={cat=Tom}}');
  });

  it('itself, nested', async () => {
    expect(await pick({ child: { child: { pet: { dog: 3 } } } })).toBe('{child={child={pet={dog=3}}}}');
  });

  it('a list of oneOf inputs inside a regular input', async () => {
    const pets = [{ cat: 'a' }, { dog: 2 }];
    expect((await client.queries.describeBasket({ basket: { pets, lead: { dog: 3 } } })).describeBasket).toBe('{lead={dog=3}, pets=[{cat=a}, {dog=2}]}');
    expect((await client.queries.describeBasket({ basket: { pets } })).describeBasket).toBe('{pets=[{cat=a}, {dog=2}]}');
    expect((await client.queries.describeBasket({ basket: { pets: [] } })).describeBasket).toBe('{pets=[]}');
  });
});
