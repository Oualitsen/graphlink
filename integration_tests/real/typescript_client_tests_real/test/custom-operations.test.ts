import { beforeEach, describe, expect, it } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import { OnlyOne, Spelling, UserStatus } from '../lib/generated/graphlink.js';
import { newClient } from './real-server-adapter.ts';

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

describe('named fragments', () => {
  it('a fragment that spreads another fragment', async () => {
    const u = (await client.queries.fragNested({ id: 'user-1' })).getUser;
    expect([u.id, u.name]).toEqual(['user-1', 'Alice Smith']);
    expect(u.status).toBe(UserStatus.Active);
  });

  it('one fragment reused by two operations', async () => {
    const all = (await client.queries.fragReuseA()).listUsers;
    expect(all.map((u) => u.id)).toEqual(expect.arrayContaining(['user-1', 'user-2']));
    const one = (await client.queries.fragReuseB({ id: 'user-2' })).getUser;
    expect([one.id, one.name]).toEqual(['user-2', 'Bob Jones']);
    expect(one.email).not.toBeNull();
  });

  it('a fragment on an interface next to an inline fragment on a member', async () => {
    const feed = (await client.queries.fragOnInterface()).feed;
    expect(feed.length).toBeGreaterThan(0);
    expect(feed.every((e) => e.id.length > 0 && e.createdBy.length > 0)).toBe(true);
  });

  it('several root fields sharing one fragment', async () => {
    const r = await client.queries.multiRoot();
    expect(r.first.name).toBe('Alice Smith');
    expect(r.second.name).toBe('Bob Jones');
    expect(r.all.map((u) => u.id)).toEqual(expect.arrayContaining(['user-1', 'user-2']));
  });
});

describe('variables', () => {
  it('defaults apply when the variable is not given', async () => {
    expect((await client.queries.varsDefaults({})).searchUsers).toHaveLength(1);
  });

  it('an explicit value replaces the default', async () => {
    expect((await client.queries.varsDefaults({ name: 'Alice', limit: 5 })).searchUsers.map((u) => u.id)).toEqual(['user-1']);
  });

  it('list, nested list and enum variables', async () => {
    const r = (await client.queries.varsLists({
      a: [1, 2], b: [1, null], c: [[1], [2, 3]], e: [Spelling.XY], f: [null, Spelling.V1],
    })).echoArgs;
    expect(r.a).toEqual([1, 2]);
    expect(r.b).toEqual([1, null]);
    expect(r.c).toEqual([[1], [2, 3]]);
    expect(r.e).toEqual([Spelling.XY]);
    expect(r.f).toEqual([null, Spelling.V1]);
  });

  it('a nullable enum variable', async () => {
    expect((await client.queries.varsEnum({ one: OnlyOne.Only })).echoArgs.one).toBe(OnlyOne.Only);
  });

  it('an input object variable', async () => {
    const r = (await client.queries.varsInput({ inner: { n: 4, label: 'x' } })).echoInner;
    expect([r.n, r.label]).toEqual([4, 'x']);
  });

  it('nullable versus non-null variables', async () => {
    const given = (await client.queries.varsNullable({ dollar: '$d', quote: 'q' })).echoNastyArgs;
    expect([given.dollar, given.quote]).toEqual(['$d', 'q']);
    const left = (await client.queries.varsNullable({ quote: 'q' })).echoNastyArgs;
    expect([left.dollar, left.quote]).toEqual([null, 'q']);
  });
});

describe('@include and @skip', () => {
  it('with variables', async () => {
    const both = (await client.queries.conditionalVars({ withEmail: true, skipName: false })).getUser;
    expect([both.id, both.name, both.email]).toEqual(['user-1', 'Alice Smith', 'alice@test.com']);
    const neither = (await client.queries.conditionalVars({ withEmail: false, skipName: true })).getUser;
    expect(neither.id).toBe('user-1');
    expect(neither.name ?? null).toBeNull();
    expect(neither.email ?? null).toBeNull();
  });

  it('with literals', async () => {
    const u = (await client.queries.conditionalLiterals()).getUser;
    expect(u.name).toBe('Alice Smith');
    expect(u.email ?? null).toBeNull();
    expect(u.status).toBe(UserStatus.Active);
    expect(u.priority ?? null).toBeNull();
  });
});

describe('aliases', () => {
  it('the same field twice with different arguments', async () => {
    const r = await client.queries.aliasesSameField();
    expect([r.a.id, r.b.id]).toEqual(['user-1', 'user-2']);
  });

  it('aliases named after keywords', async () => {
    const r = (await client.queries.aliasKeywords()).class;
    expect(r.default).toBe('Alice Smith');
    expect(r.import).toBe('user-1');
  });

  it('an alias with the name of another field', async () => {
    expect((await client.queries.aliasEqualsOtherField()).getUser.name).toBe('alice@test.com');
  });
});

describe('operation names that collide with something', () => {
  it('with a type', async () => {
    expect((await client.queries.user()).getUser.id).toBe('user-1');
    expect((await client.queries.photo2()).photo!.id).toBe('ph1');
  });

  it('with a keyword', async () => {
    expect((await client.queries.return()).listUsers.length).toBeGreaterThan(0);
  });

  it('with the name of an auto-generated operation, the custom one wins', async () => {
    expect((await client.queries.shelf()).shelf.id).toBe('s1');
  });

  it('with the name of a generated response type', async () => {
    expect((await client.queries.getUserResponse()).getUser.id).toBe('user-1');
  });
});

describe('field arguments of every shape', () => {
  it('literals', async () => {
    expect((await client.queries.shelfItems()).shelf.items).toEqual(['tags=[a, b]', 'kind=x__y', 'filter={n=3, label=L}', 'limit=5']);
  });

  it('variables', async () => {
    const r = (await client.queries.shelfItemsVars({ tags: ['t'], kind: Spelling.V1, filter: { n: 1, label: 'f' }, limit: 7 })).shelf;
    expect(r.items).toEqual(['tags=[t]', 'kind=v1', 'filter={n=1, label=f}', 'limit=7']);
  });

  it('server-side defaults of a field argument', async () => {
    expect((await client.queries.shelfItemsDefaults()).shelf.items.at(-1)).toBe('limit=2');
  });
});

describe('literal arguments', () => {
  it('lists, nulls and enums', async () => {
    const r = (await client.queries.literalLists()).echoArgs;
    expect(r.a).toEqual([1, 2, 3]);
    expect(r.b).toEqual([1, null]);
    expect(r.c).toEqual([[1], [2, 3]]);
    expect(r.e).toEqual([Spelling.A, Spelling.XY]);
    expect(r.f).toEqual([null, Spelling.V1]);
    expect(r.g).toEqual([Spelling.SnakeCase2]);
    expect(r.one).toBe(OnlyOne.Only);
  });

  it('an input object', async () => {
    const r = (await client.queries.literalInput()).echoInput;
    expect(r.a).toEqual([4]);
    expect(r.b).toEqual([null, 5]);
    expect(r.c).toEqual([[6]]);
    expect(r.e).toEqual([Spelling.B2]);
    expect(r.f).toEqual([null]);
    expect(r.g).toEqual([Spelling.A]);
  });

  it('every scalar kind', async () => {
    const r = (await client.queries.literalScalars()).echoEverything;
    expect([r.i, r.neg, r.big]).toEqual([5, -3, 9]);
    expect([r.f, r.exp]).toEqual([2.5, 100]);
    expect([r.b, r.bf]).toEqual([false, true]);
    expect([r.s, r.id, r.e]).toEqual(['lit', 'q', Spelling.V1]);
    expect(r.ints).toEqual([9]);
    expect(r.nested).toEqual([[1]]);
    expect([r.inner!.n, r.inner!.label]).toEqual([2, 'L']);
    expect(r.nothing).toBeNull();
    expect(r.emptyList).toEqual([]);
    expect(r.emptyObj!.n).toBeNull();
  });

  it('mixed with variables', async () => {
    const r = (await client.queries.literalsMixed({ a: [8], one: OnlyOne.Only })).echoArgs;
    expect(r.a).toEqual([8]);
    expect(r.e).toEqual([Spelling.A, Spelling.B2]);
    expect(r.f).toEqual([Spelling.V1]);
    expect(r.one).toBe(OnlyOne.Only);
  });
});
