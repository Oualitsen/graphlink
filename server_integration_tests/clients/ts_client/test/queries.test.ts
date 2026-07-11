import { describe, test, expect } from 'vitest';
import { newClient } from './fixtures.js';

describe('getAuthor', () => {
  const client = newClient();

  test('returns author by id', async () => {
    const res = await client.queries.getAuthor({ id: '1', fieldArgs: { latestArticlesLimit: 10 } });
    expect(res.getAuthor).not.toBeNull();
    expect(res.getAuthor!.id).toBe('1');
    expect(res.getAuthor!.name).toBe('Ramdane');
  });

  test('returns null for unknown id', async () => {
    const res = await client.queries.getAuthor({ id: 'missing', fieldArgs: { latestArticlesLimit: 10 } });
    expect(res.getAuthor).toBeNull();
  });

  test('articles is resolved via batch DataLoader mapping', async () => {
    const res = await client.queries.getAuthor({ id: '1', fieldArgs: { latestArticlesLimit: 10 } });
    const titles = res.getAuthor!.articles?.map(a => a.title);
    expect(titles).toEqual(expect.arrayContaining(['GraphLink Basics', 'Advanced GraphLink']));
  });

  test('latestArticles is resolved via non-batch mapping with arguments', async () => {
    const res = await client.queries.getAuthor({ id: '1', fieldArgs: { latestArticlesLimit: 10 } });
    const titles = res.getAuthor!.latestArticles?.map(a => a.title);
    expect(titles).toEqual(expect.arrayContaining(['GraphLink Basics', 'Advanced GraphLink']));
  });
});

describe('getAuthorWithoutArticle', () => {
  const client = newClient();

  test('does not require a limit argument when articles are not projected', async () => {
    const res = await client.queries.getAuthorWithoutArticle({ id: '1' });
    expect(res.getAuthor).not.toBeNull();
    expect(res.getAuthor!.id).toBe('1');
    expect(res.getAuthor!.name).toBe('Ramdane');
  });
});

describe('getArticle', () => {
  const client = newClient();

  test('returns article by id', async () => {
    const res = await client.queries.getArticle({ id: '1', fieldArgs: { latestArticlesLimit: 2 } });
    expect(res.getArticle.id).toBe('1');
    expect(res.getArticle.title).toBe('GraphLink Basics');
  });

  test('author is resolved via non-batch schema mapping', async () => {
    const res = await client.queries.getArticle({ id: '1', fieldArgs: { latestArticlesLimit: 2 } });
    expect(res.getArticle.author?.id).toBe('1');
    expect(res.getArticle.author?.name).toBe('Ramdane');
  });
});

describe('getAuthorAndArticle', () => {
  const client = newClient();

  test('resolves both root fields with their own arguments plus a shared fragment argument', async () => {
    const res = await client.queries.getAuthorAndArticle({ authorId: '1', articleId: '3', fieldArgs: { latestArticlesLimit: 1 } });
    expect(res.author!.id).toBe('1');
    expect(res.author!.latestArticles).toHaveLength(1);
    expect(res.article.id).toBe('3');
    expect(res.article.title).toBe("Alice's First Post");
  });
});

describe('listAuthors / listArticles', () => {
  const client = newClient();

  test('listAuthors returns all authors', async () => {
    const res = await client.queries.listAuthors({ fieldArgs: { latestArticlesLimit: 10 } });
    expect(res.listAuthors.map(a => a.id)).toEqual(expect.arrayContaining(['1', '2']));
  });

  test('listArticles returns all articles', async () => {
    const res = await client.queries.listArticles({ fieldArgs: { latestArticlesLimit: 2 } });
    expect(res.listArticles.map(a => a.id)).toContain('1');
  });
});
