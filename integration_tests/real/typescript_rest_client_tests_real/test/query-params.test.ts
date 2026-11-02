import { beforeEach, describe, expect, it } from 'vitest';
import { Status, type GraphLinkClient } from '../lib/generated/graphlink';
import { header, newClient, queryPairs, queryValue, resetServer } from './support';
import { variant } from './variant';

let client: GraphLinkClient;

beforeEach(async () => {
  await resetServer();
  client = newClient();
});

describe('scalars and paths', () => {
  it('every scalar kind is a query value; defaults are sent; nulls are omitted', async () => {
    const e = await client.queries.eScalars({
      id: 'x1', s: 'hello', i: 3, f: 2.5, b: true, st: Status.Archived, renamed: 'r',
    });
    expect(e.method).toBe('GET');
    expect(e.path).toBe('/echo/scalars/x1');
    expect(queryPairs(e)).toEqual(['s=hello', 'i=3', 'f=2.5', 'b=true', 'st=ARCHIVED', 'dflt=5', 'x-ren=r']);
    expect(e.bodySize).toBe(0);
    expect(e.contentType).toBeNull();
    expect(header(e, 'accept')).toBe('application/json');
  });

  it('an omitted optional is absent, a default still goes out, an explicit value replaces it', async () => {
    expect(queryPairs(await client.queries.eScalars({ id: 'x1' }))).toEqual(['dflt=5']);
    expect(queryPairs(await client.queries.eScalars({ id: 'x1', dflt: 9 }))).toEqual(['dflt=9']);
  });

  it('false and 0 are values, not omissions', async () => {
    const e = await client.queries.eScalars({ id: 'x1', b: false, i: 0, s: '' });
    expect(queryPairs(e)).toEqual(['s=', 'i=0', 'b=false', 'dflt=5']);
  });

  it('path segments and query values survive reserved and non-ASCII characters', async () => {
    const segment = 'a b/c?d#é+%';
    const value = 'a&b=c d+e/é"%25';
    const e = await client.queries.eSpecial({ segment, q: value, other: 'ü' });
    expect(e.path).toBe(`/echo/special/${encodeURIComponent(segment)}/tail`);
    expect(queryValue(e, 'q')).toBe(value);
    expect(queryValue(e, 'other')).toBe('ü');
  });

  it('an empty string path segment is not silently dropped', async () => {
    const e = await client.queries.eSpecial({ segment: 'seg', q: '' });
    expect(queryValue(e, 'q')).toBe('');
  });

  it('DELETE carries its arguments in the query and sends no body', async () => {
    const e = await client.queries.eDeleteQuery({ id: 'd1', force: true });
    expect(e.method).toBe('DELETE');
    expect(e.path).toBe('/echo/delete/d1');
    expect(queryPairs(e)).toEqual(['force=true']);
    expect(e.bodySize).toBe(0);
  });
});

describe('lists', () => {
  it('scalar lists repeat the key (or join with commas); empty lists send nothing', async () => {
    const e = await client.queries.eLists({ tags: ['a', 'b c'], ids: [1, 2, 3], empty: [] });
    expect(queryPairs(e)).toEqual([...variant.list('tags', ['a', 'b c']), ...variant.list('ids', ['1', '2', '3'])]);
    expect(queryValue(e, 'empty')).toBeUndefined();
  });

  it('a matrix uses indexed keys at both levels', async () => {
    const e = await client.queries.eLists({ matrix: [[1, 2], [3]] });
    expect(queryPairs(e)).toEqual([
      `${variant.key('matrix', [0, 0])}=1`,
      `${variant.key('matrix', [0, 1])}=2`,
      `${variant.key('matrix', [1, 0])}=3`,
    ]);
  });

  it('a list of objects uses indexed keys and scalar lists inside objects repeat', async () => {
    const e = await client.queries.eLists({ rows: [{ name: 'r0', ids: [1, 2] }, { name: 'r1' }] });
    expect(queryPairs(e)).toEqual([
      `${variant.key('rows', [0, 'name'])}=r0`,
      ...variant.list(variant.key('rows', [0, 'ids']), ['1', '2']),
      `${variant.key('rows', [1, 'name'])}=r1`,
    ]);
  });

  it('list items with reserved characters round-trip', async () => {
    const e = await client.queries.eLists({ tags: ['a&b', 'c=d', 'e f', 'é'] });
    const joined = variant.comma
      ? queryValue(e, 'tags')
      : e.query.filter((p) => p.name === 'tags').map((p) => p.value).join('|');
    expect(joined).toBe(variant.comma ? 'a&b,c=d,e f,é' : 'a&b|c=d|e f|é');
  });
});

describe('objects', () => {
  it('an input is spread by default: one key per field, the argument name is not sent', async () => {
    const e = await client.queries.eObjects({ filter: { tag: 'x', minPrice: 3, status: Status.Active } });
    expect(queryPairs(e)).toEqual(['tag=x', 'minPrice=3', 'status=ACTIVE']);
  });

  it('a spread input with unset fields sends only the set ones', async () => {
    const e = await client.queries.eObjects({ filter: { tag: 'x' } });
    expect(queryPairs(e)).toEqual(['tag=x']);
  });

  it('FLAT nests with the configured separator, at any depth', async () => {
    const e = await client.queries.eObjects({
      meta: {
        name: 'm',
        tags: ['t1', 't2'],
        address: { city: 'Oran', street: 'Rue 1', geo: { lat: 35.7, lng: -0.6 } },
      },
    });
    expect(queryPairs(e)).toEqual([
      `${variant.key('meta', ['name'])}=m`,
      ...variant.list(variant.key('meta', ['tags']), ['t1', 't2']),
      `${variant.key('meta', ['address', 'city'])}=Oran`,
      `${variant.key('meta', ['address', 'street'])}=Rue 1`,
      `${variant.key('meta', ['address', 'geo', 'lat'])}=35.7`,
      `${variant.key('meta', ['address', 'geo', 'lng'])}=-0.6`,
    ]);
  });

  it('encoding JSON sends one key holding the JSON text', async () => {
    const e = await client.queries.eObjects({ asJson: { name: 'm', tags: ['a'], address: { city: 'c' } } });
    expect(e.query.map((p) => p.name)).toEqual(['j']);
    const json = JSON.parse(queryValue(e, 'j')!) as Record<string, unknown>;
    expect(json['name']).toBe('m');
    expect(json['tags']).toEqual(['a']);
    expect((json['address'] as Record<string, unknown>)['city']).toBe('c');
  });

  it('several roles in one call keep their own keys', async () => {
    const e = await client.queries.eObjects({ filter: { tag: 'x' }, meta: { name: 'm' }, asJson: { name: 'j' } });
    expect(new Set(e.query.map((p) => p.name))).toEqual(new Set(['tag', variant.key('meta', ['name']), 'j']));
  });
});
