import { describe, expect, it } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client';
import { createFetchAdapter } from '../lib/generated/client/graph-link-adapters';
import { createRestFetchAdapter } from '../lib/generated/client/graph-link-rest-adapters';
import { ArticleNotFound } from '../lib/generated/errors/article-not-found';
import { Banned } from '../lib/generated/errors/banned';
import { Forbidden } from '../lib/generated/errors/forbidden';
import { TitleTaken } from '../lib/generated/errors/title-taken';
import { GraphLinkDomainError } from '../lib/generated/client/graph-link-domain-error';
import { Reason } from '../lib/generated/enums/reason';

const client = new GraphLinkClient(createFetchAdapter('http://127.0.0.1:9930/graphql'), createRestFetchAdapter('http://127.0.0.1:9930'));

async function thrownBy(call: () => Promise<unknown>): Promise<unknown> {
  try {
    await call();
  } catch (e) {
    return e;
  }
  throw new Error('expected an exception');
}

describe('queries', () => {
  it('a successful call returns its data', async () => {
    const res = await client.queries.article({ id: '1' });
    expect(res.article?.id).toBe('1');
  });

  it('a declared error is thrown as its class and carries its fields', async () => {
    const e = await thrownBy(() => client.queries.article({ id: 'missing' }));
    expect(e).toBeInstanceOf(ArticleNotFound);
    expect(e).toBeInstanceOf(GraphLinkDomainError);
    expect(e).toBeInstanceOf(Error);
    expect((e as ArticleNotFound).id).toBe('missing');
    expect((e as ArticleNotFound).message).toBe('Article missing not found');
  });

  it('an error matched on a custom field and value', async () => {
    const e = await thrownBy(() => client.queries.article({ id: 'forbidden' }));
    expect(e).toBeInstanceOf(Forbidden);
    expect((e as Forbidden).message).toBe('No access');
  });

  it('an error of another root field', async () => {
    expect(await thrownBy(() => client.queries.secret())).toBeInstanceOf(Forbidden);
  });

  it.each(['other-code', 'no-field', 'no-path', 'no-extensions'])('%s keeps the original errors array', async (id) => {
    const e = await thrownBy(() => client.queries.article({ id }));
    expect(Array.isArray(e)).toBe(true);
    expect(e).not.toBeInstanceOf(GraphLinkDomainError);
  });

  it('an unknown code keeps its message', async () => {
    const e = (await thrownBy(() => client.queries.article({ id: 'other-code' }))) as Array<{ message: string }>;
    expect(e[0].message).toBe('A new error');
  });

  it('an operation without @glThrows keeps the errors array', async () => {
    const e = await thrownBy(() => client.queries.plain({ id: '1' }));
    expect(Array.isArray(e)).toBe(true);
  });

  it('a combined query keeps the errors array', async () => {
    const e = (await thrownBy(() => client.queries.pair())) as Array<{ path: unknown[] }>;
    expect(Array.isArray(e)).toBe(true);
    expect(e[0].path).toEqual(['first']);
  });

  it('a capture-errors operation returns the errors and throws nothing', async () => {
    const res = await client.queries.captured();
    expect(res.errors?.[0].extensions?.['code']).toBe('ArticleNotFound');
  });
});

describe('mutations', () => {
  it('a successful call returns its data', async () => {
    const res = await client.mutations.createArticle({ input: { title: 'fresh' } });
    expect(res.createArticle?.id).toBe('fresh');
  });

  it('a declared error carries a list field', async () => {
    const e = await thrownBy(() => client.mutations.createArticle({ input: { title: 'taken' } }));
    expect(e).toBeInstanceOf(TitleTaken);
    expect((e as TitleTaken).title).toBe('taken');
    expect((e as TitleTaken).suggestions).toEqual(['taken-2']);
  });

  it('an error with its own value, an enum and an optional field', async () => {
    const e = await thrownBy(() => client.mutations.createArticle({ input: { title: 'banned' } }));
    expect(e).toBeInstanceOf(Banned);
    expect((e as Banned).reason).toBe(Reason.Spam);
    expect((e as Banned).until).toBe(5);
  });
});
