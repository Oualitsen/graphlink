import { beforeEach, describe, expect, it } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { Mood, Spelling } from '../lib/generated/graphlink.js';
import { defaultEverythingInput } from '../lib/generated/graphlink.js';
import { newClient } from './real-server-adapter.ts';

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

const nasty = {
  dollar: 'cost $5 and ${x} and $$',
  quote: 'say "hi" it\'s',
  backslash: 'C:\\dir\\file\\n',
  newline: 'line1\nline2\ttab',
  percent: '100% {braces} {{x}} %s %d',
  comments: 'a */ b // c /* d',
  triple: '""" \'\'\' ```',
  unicode: 'café 中 😀',
  nonAscii: 'é中😀',
};

describe('string defaults with special characters', () => {
  it('on operation arguments', async () => {
    expect((await client.queries.echoNastyArgs({})).echoNastyArgs).toEqual(nasty);
  });

  it('on input fields, through an input argument that defaults to {}', async () => {
    expect((await client.queries.echoNasty({})).echoNasty).toEqual(nasty);
  });

  it('an explicit value replaces the default', async () => {
    const r = (await client.queries.echoNastyArgs({ dollar: '$y' })).echoNastyArgs;
    expect(r.dollar).toBe('$y');
    expect(r.quote).toBe(nasty.quote);
  });
});

it('string literals written inline in an operation', async () => {
  const r = (await client.queries.nastyLiteral()).echoNastyArgs;
  expect(r).toEqual({
    dollar: 'cost $5 ${x}', quote: 'say "hi"', backslash: 'C:\\dir', newline: 'a\nb', unicode: 'é😀', triple: 'block "x" ',
  });
});

describe('defaults of every kind', () => {
  it('scalars, enum, lists, nested input, null', async () => {
    const r = (await client.queries.echoEverything({ input: { ...defaultEverythingInput } })).echoEverything;
    expect(r).toMatchObject({
      i: 42, neg: -7, big: 2147483647, f: 3.14, exp: 1000, b: true, bf: false, s: 'x', id: 'abc',
      e: Spelling.XY, ints: [1, 2, 3], nested: [[1], [2, 3]], nothing: null, emptyList: [],
    });
    expect(r.inner).toMatchObject({ n: 5, label: 'inner' });
    expect(r.emptyObj).toMatchObject({ n: 1, label: 'dflt' });
  });

  it('an argument whose input type has its own defaults', async () => {
    const r = (await client.queries.echoInner({})).echoInner;
    expect(r).toEqual({ n: 9, label: 'dflt', tags: ['a'] });
  });
});

describe('recursive inputs', () => {
  it('a tree', async () => {
    const r = (await client.queries.treeStats({
      tree: { value: 1, children: [{ value: 2, children: [{ value: 4 }] }, { value: 3 }] },
    })).treeStats;
    expect(r.flat).toEqual([1, 2, 4, 3]);
    expect(r.depth).toBe(3);
  });

  it('mutually recursive inputs', async () => {
    const r = (await client.queries.pingLength({ ping: { n: 1, pong: { n: 2, ping: { n: 3 } } } })).pingLength;
    expect(r).toBe(3);
  });
});

describe('@oneOf input', () => {
  it('the first member', async () => {
    expect((await client.queries.describePet({ pet: { cat: 'Tom' } })).describePet).toBe('cat:Tom');
  });

  it('the second member', async () => {
    expect((await client.queries.describePet({ pet: { dog: 3 } })).describePet).toBe('dog:3');
  });
});

describe('@deprecated', () => {
  it('deprecated fields, arguments and enum values still work', async () => {
    const r = (await client.queries.legacy({ withReason: 'a', plain: 'b' })).legacy;
    expect(r.old).toBe('a');
    expect(r.older).toBe('b');
    expect(r.mood).toBe(Mood.Calm);
  });
});
