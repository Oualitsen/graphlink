import { describe, test, expect } from 'vitest';
import { Priority } from '../src/generated/enums/priority.js';
import { newClient } from './fixtures.js';

describe('createArticle', () => {
  const client = newClient();

  test('returns the created article with given input', async () => {
    const res = await client.mutations.createArticle({
      input: { title: 'New Post', authorId: '2' },
      fieldArgs: { latestArticlesLimit: 2 },
    });
    expect(res.createArticle.title).toBe('New Post');
    expect(res.createArticle.authorId).toBe('2');
    expect(res.createArticle.id).not.toBe('');
  });
});

describe('updateArticle', () => {
  const client = newClient();

  test('updates the title and returns the article', async () => {
    const created = await client.mutations.createArticle({
      input: { title: 'Original Title', authorId: '1' },
      fieldArgs: { latestArticlesLimit: 2 },
    });
    const res = await client.mutations.updateArticle({
      input: { id: created.createArticle.id, title: 'Updated Title' },
      fieldArgs: { latestArticlesLimit: 2 },
    });
    expect(res.updateArticle.id).toBe(created.createArticle.id);
    expect(res.updateArticle.title).toBe('Updated Title');
  });
});

describe('deleteArticle', () => {
  const client = newClient();

  test('returns true when article exists', async () => {
    const created = await client.mutations.createArticle({
      input: { title: 'To Delete', authorId: '1' },
      fieldArgs: { latestArticlesLimit: 2 },
    });
    const res = await client.mutations.deleteArticle({ id: created.createArticle.id });
    expect(res.deleteArticle).toBe(true);
  });

  test('returns false when article does not exist', async () => {
    const res = await client.mutations.deleteArticle({ id: 'missing-id' });
    expect(res.deleteArticle).toBe(false);
  });
});

describe('ackPriority', () => {
  const client = newClient();

  test('enum mutation argument deserializes; returns constant ack', async () => {
    const res = await client.mutations.ackPriority({ level: Priority.High });
    expect(res.ackPriority).toBe('OK');
  });
});
