import { describe, test, expect } from 'vitest';
import { newClient } from './fixtures.js';
import type { ArticleCreatedResponse } from '../src/generated/types/article-created-response.js';
import type { ArticleUpdatedResponse } from '../src/generated/types/article-updated-response.js';

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

describe('articleCreated', () => {
  test('emits when an article is created', async () => {
    const client = newClient();

    const eventPromise = new Promise<ArticleCreatedResponse>((resolve, reject) => {
      const timer = setTimeout(() => {
        unsubscribe();
        reject(new Error('Timeout waiting for articleCreated event'));
      }, 10000);

      const unsubscribe = client.subscriptions.articleCreated(
        { fieldArgs: { latestArticlesLimit: 2 } },
        (data) => {
          clearTimeout(timer);
          unsubscribe();
          resolve(data);
        },
        (err) => {
          clearTimeout(timer);
          unsubscribe();
          reject(err);
        },
      );
    });

    // give the subscription a moment to register before triggering the mutation
    await sleep(300);

    const created = await client.mutations.createArticle({
      input: { title: 'Subscribed Post', authorId: '1' },
      fieldArgs: { latestArticlesLimit: 2 },
    });

    const event = await eventPromise;
    expect(event.articleCreated.id).toBe(created.createArticle.id);
    expect(event.articleCreated.title).toBe('Subscribed Post');
  });
});

describe('articleUpdated', () => {
  test('emits when the matching article is updated', async () => {
    const client = newClient();

    const created = await client.mutations.createArticle({
      input: { title: 'Will Update', authorId: '2' },
      fieldArgs: { latestArticlesLimit: 2 },
    });

    const eventPromise = new Promise<ArticleUpdatedResponse>((resolve, reject) => {
      const timer = setTimeout(() => {
        unsubscribe();
        reject(new Error('Timeout waiting for articleUpdated event'));
      }, 10000);

      const unsubscribe = client.subscriptions.articleUpdated(
        { id: created.createArticle.id, fieldArgs: { latestArticlesLimit: 2 } },
        (data) => {
          clearTimeout(timer);
          unsubscribe();
          resolve(data);
        },
        (err) => {
          clearTimeout(timer);
          unsubscribe();
          reject(err);
        },
      );
    });

    await sleep(300);

    const updated = await client.mutations.updateArticle({
      input: { id: created.createArticle.id, title: 'Updated via subscription' },
      fieldArgs: { latestArticlesLimit: 2 },
    });

    const event = await eventPromise;
    expect(event.articleUpdated.id).toBe(updated.updateArticle.id);
    expect(event.articleUpdated.title).toBe('Updated via subscription');
  });
});
