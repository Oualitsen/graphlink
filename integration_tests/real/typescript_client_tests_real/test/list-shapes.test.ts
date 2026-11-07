import { beforeEach, describe, expect, it } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { ArgOnly, OnlyOne, Phase, RespOnly, Spelling } from '../lib/generated/graphlink.js';
import type { Phased } from '../lib/generated/graphlink.js';
import { newClient } from './real-server-adapter.ts';

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

const shapes = async (mode: string) => (await client.queries.listShapes({ mode })).listShapes;
const known = Object.values(Spelling).filter((v): v is Spelling => typeof v === 'string' && v !== Spelling.unknownValue__);

describe('list shapes with real null elements', () => {
  it('scalars', async () => {
    const s = await shapes('full');
    expect(s.a).toEqual([1, 2, 3]);
    expect(s.b).toEqual([1, 2, 3]);
    expect(s.c).toEqual([1, null, 3]);
    expect(s.d).toEqual([null]);
  });

  it('nested lists', async () => {
    const s = await shapes('full');
    expect(s.e).toEqual([[1, 2], [3]]);
    expect(s.f).toEqual([[1, null], null]);
  });

  it('enums', async () => {
    expect((await shapes('full')).g).toEqual([Spelling.A, null, Spelling.B2]);
  });

  it('objects, union members and interface implementers', async () => {
    const s = await shapes('full');
    expect(s.h.map((v) => v?.width ?? null)).toEqual([640, null]);
    expect(s.i.map((v) => v?.__typename ?? null)).toEqual(['Photo', null, 'Video']);
    expect(s.j.map((v) => v?.__typename ?? null)).toEqual(['Comment', null]);
  });
});

describe('empty list versus null list', () => {
  it('empty lists stay empty', async () => {
    const s = await shapes('empty');
    expect(s.b).toEqual([]);
    expect(s.d).toEqual([]);
    expect(s.f).toEqual([]);
    expect(s.e).toEqual([]);
  });

  it('null lists stay null while the required ones are empty', async () => {
    const s = await shapes('null');
    expect(s.b).toBeNull();
    expect(s.d).toBeNull();
    expect(s.f).toBeNull();
    expect(s.a).toEqual([]);
    expect(s.g).toEqual([]);
    expect(s.i).toEqual([]);
  });
});

describe('list arguments', () => {
  it('every shape round trips', async () => {
    const r = (await client.queries.echoArgs({
      a: [1, 2], b: [1, null], c: [[1], [], [2, 3]],
      e: [Spelling.XY, Spelling.Http2Ok], f: [null, Spelling.V1],
    })).echoArgs;
    expect(r.a).toEqual([1, 2]);
    expect(r.b).toEqual([1, null]);
    expect(r.c).toEqual([[1], [], [2, 3]]);
    expect(r.e).toEqual([Spelling.XY, Spelling.Http2Ok]);
    expect(r.f).toEqual([null, Spelling.V1]);
  });

  it('omitted lists come back null, defaults are applied', async () => {
    const r = (await client.queries.echoArgs({ a: [], e: [] })).echoArgs;
    expect(r.b).toBeNull();
    expect(r.c).toBeNull();
    expect(r.f).toBeNull();
    expect(r.g).toEqual([Spelling.A, Spelling.B2]);
    expect(r.one).toBe(OnlyOne.Only);
  });

  it('an explicitly empty default-bearing list is not replaced by the default', async () => {
    expect((await client.queries.echoArgs({ a: [], e: [], g: [] })).echoArgs.g).toEqual([]);
  });
});

describe('list input fields', () => {
  it('every shape round trips', async () => {
    const r = (await client.queries.echoInput({
      input: { a: [3, 4], b: [null, 5], c: [[1, 2], []], e: [Spelling.SnakeCase2], f: [Spelling.A, null], g: [Spelling.V1] },
    })).echoInput;
    expect(r.a).toEqual([3, 4]);
    expect(r.b).toEqual([null, 5]);
    expect(r.c).toEqual([[1, 2], []]);
    expect(r.e).toEqual([Spelling.SnakeCase2]);
    expect(r.f).toEqual([Spelling.A, null]);
    expect(r.g).toEqual([Spelling.V1]);
  });

  it('input defaults reach the server', async () => {
    const r = (await client.queries.echoInput({ input: { a: [], e: [] } })).echoInput;
    expect(r.g).toEqual([Spelling.A, Spelling.B2]);
    expect(r.one).toBe(OnlyOne.Only);
  });
});

describe('large lists', () => {
  it('50000 scalars', async () => {
    const r = (await client.queries.bigInts({ n: 50000 })).bigInts;
    expect(r).toHaveLength(50000);
    expect(r[49999]).toBe(49999);
  });

  it('20000 objects', async () => {
    const r = (await client.queries.bigPhotos({ n: 20000 })).bigPhotos;
    expect(r).toHaveLength(20000);
    expect(r[19999].id).toBe('p19999');
    expect(r[19999].width).toBe(19999);
  });
});

describe('enum spellings', () => {
  it('every spelling round trips through a list argument', async () => {
    const r = (await client.queries.echoArgs({ a: [], e: known })).echoArgs;
    expect(r.e).toEqual(known);
  });

  it('wire names are the declared ones', () => {
    expect(known.map((v) => Spelling.toJson(v))).toEqual(['A', 'B2', 'x__y', 'http2_ok', 'v1', 'snake_case_2']);
  });

  it('an enum used only as an argument', async () => {
    expect((await client.queries.argOnly({ v: ArgOnly.P2 })).argOnly).toBe('P2');
  });

  it('an enum used only in a response', async () => {
    expect((await client.queries.respOnly()).respOnly).toBe(RespOnly.R2);
  });
});

describe('unknown enum value sent by the server', () => {
  it('in a field', async () => {
    const p = (await client.queries.phaseProbe()).phaseProbe;
    expect(p.single).toBe(Phase.unknownValue__);
    expect(p.maybe).toBe(Phase.unknownValue__);
  });

  it('in list elements, known ones untouched', async () => {
    const p = (await client.queries.phaseProbe()).phaseProbe;
    expect(p.list).toEqual([Phase.Open, Phase.unknownValue__, Phase.Closed]);
    expect(p.nullableList).toEqual([Phase.unknownValue__, null]);
  });

  it('in a union member', async () => {
    const h = (await client.queries.phaseHolder()).phaseHolder as Phased;
    expect(h.phase).toBe(Phase.unknownValue__);
  });
});
