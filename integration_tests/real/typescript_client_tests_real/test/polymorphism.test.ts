import { beforeEach, describe, expect, it } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import type { Article, Comment, Document, Photo, Video } from '../lib/generated/graphlink.js';
import { httpAdapterForPort, newClient, newWsAdapterForPort, realHttpAdapter, WS_URL } from './real-server-adapter.ts';
import { DefaultGraphLinkWsAdapter } from '../lib/generated/graphlink.ts';

let client: GraphLinkClient;
beforeEach(() => { client = newClient(); });

const kinds = (values: ReadonlyArray<{ __typename: string } | null | undefined>) => values.map((v) => v?.__typename ?? null);

describe('union results', () => {
  it('a union member per id', async () => {
    const photo = (await client.queries.attachment({ id: 'ph1' })).attachment;
    const video = (await client.queries.attachment({ id: 'v1' })).attachment;
    const document = (await client.queries.attachment({ id: 'd1' })).attachment;
    expect(photo!.__typename).toBe('Photo');
    expect((photo as Photo).width).toBe(640);
    expect((video as Video).seconds).toBe(30);
    expect((document as Document).pages).toBe(12);
  });

  it('a nullable union decodes null', async () => {
    expect((await client.queries.attachment({ id: 'nope' })).attachment).toBeNull();
  });

  it('a list of union members', async () => {
    const list = (await client.queries.attachments()).attachments;
    expect(kinds(list)).toEqual(['Photo', 'Video', 'Document']);
  });

  it('null elements in a list of unions', async () => {
    const list = (await client.queries.attachmentsNullable()).attachmentsNullable!;
    expect(kinds(list)).toEqual(['Photo', null, 'Document']);
  });

  it('a union returned by a mutation', async () => {
    for (const [kind, typename] of [['photo', 'Photo'], ['video', 'Video'], ['document', 'Document']]) {
      const created = (await client.mutations.addAttachment({ articleId: 'a1', url: 'u', kind })).addAttachment;
      expect(created.__typename, kind).toBe(typename);
    }
  });

  it('a server error on a union mutation throws', async () => {
    await expect(client.mutations.addAttachment({ articleId: 'a1', url: 'u', kind: 'bogus' })).rejects.toThrow();
  });
});

describe('interface results', () => {
  it('a list of an interface implementing another interface', async () => {
    const feed = (await client.queries.feed()).feed;
    expect(kinds(feed)).toEqual(['Article', 'Comment', 'Article', 'Comment']);
    expect(feed.map((e) => e.createdBy)).toEqual(['alice', 'bob', 'bob', 'alice']);
  });

  it('a nullable interface returns each implementation or null', async () => {
    expect((await client.queries.node({ id: 'a1' })).node!.__typename).toBe('Article');
    expect((await client.queries.node({ id: 'c1' })).node!.__typename).toBe('Comment');
    expect((await client.queries.node({ id: 'zzz' })).node).toBeNull();
  });
});

describe('nesting', () => {
  it('a union field and a list of unions inside an object', async () => {
    const article = (await client.queries.article({ id: 'a1' })).article;
    expect(article.cover!.__typename).toBe('Photo');
    expect(kinds(article.attachments)).toEqual(['Photo', 'Video', 'Document']);
  });

  it('null polymorphic fields', async () => {
    const article = (await client.queries.article({ id: 'a2' })).article;
    expect(article.cover).toBeNull();
    expect(article.attachments).toEqual([]);
    expect(article.related).toBeNull();
  });

  it('null elements in a list of interfaces', async () => {
    const related = (await client.queries.article({ id: 'a1' })).article.related!;
    expect(kinds(related)).toEqual(['Comment', null]);
  });

  it('an interface field pointing back at an implementer', async () => {
    const reply = (await client.queries.feed()).feed[3] as Comment;
    expect(reply.parent!.__typename).toBe('Article');
    expect((reply.parent as Article).title).toBe('Hello');
  });
});

describe('errors and caching', () => {
  it('an unknown article is an error', async () => {
    await expect(client.queries.article({ id: 'zzz' })).rejects.toThrow();
  });

  it('captured errors on a union operation', async () => {
    const ok = await client.queries.attachmentOrErrors({ id: 'ph1' });
    expect(ok.errors).toBeNull();
    expect(ok.data!.attachmentOrErrors!.__typename).toBe('Photo');
    const failed = await client.queries.attachmentOrErrors({ id: 'boom' });
    expect(failed.data!.attachmentOrErrors).toBeNull();
    expect(failed.errors![0].message).not.toBe('');
  });

  it('a cached union operation is served once', async () => {
    let calls = 0;
    const real = httpAdapterForPort(9988);
    const counting = new GraphLinkClient(async (payload) => { calls++; return real(payload); }, newWsAdapterForPort(9988));
    const first = (await counting.queries.getCachedAttachment({ id: 'v1' })).getCachedAttachment;
    const second = (await counting.queries.getCachedAttachment({ id: 'v1' })).getCachedAttachment;
    expect(first!.__typename).toBe('Video');
    expect(second!.__typename).toBe('Video');
    expect(calls).toBe(1);
  });
});

type Json = Record<string, any>;

describe('custom queries', () => {
  it('inline fragments on every member of a union', async () => {
    const photo = (await client.queries.fetchAttachment({ id: 'ph1' })).attachment;
    const video = (await client.queries.fetchAttachment({ id: 'v1' })).attachment;
    const document = (await client.queries.fetchAttachment({ id: 'd1' })).attachment;
    expect((photo as Photo).width).toBe(640);
    expect((video as Video).seconds).toBe(30);
    expect((document as Document).pages).toBe(12);
    expect((await client.queries.fetchAttachment({ id: 'nope' })).attachment).toBeNull();
  });

  it('one fragment shared by two root fields', async () => {
    const res = await client.queries.fetchArticleAndAttachment({ articleId: 'a1', attachmentId: 'v1' });
    expect(res.article.cover!.__typename).toBe('Photo');
    expect(res.attachment!.__typename).toBe('Video');
  });
});

describe('selections of one abstract type that differ between queries', () => {
  it('an interface selection with inline fragments and a shared fragment', async () => {
    const feed = (await client.queries.fetchFeed()).feed as Json[];
    expect(feed.map((e) => e.__typename)).toEqual(['Article', 'Comment', 'Article', 'Comment']);
    expect(feed[0].title).toBe('Hello');
    expect(feed[0].cover.url).toBe('http://cdn/1.png');
    expect(feed[0].attachments.map((a: Json) => a.id)).toEqual(['ph1', 'v1', 'd1']);
    expect(feed[1].text).toBe('Nice');
    expect(feed[2].cover).toBeNull();
  });

  it('an interface selection that names only some implementers', async () => {
    const article = (await client.queries.fetchNode({ id: 'a1' })).node as Json;
    expect(article.title).toBe('Hello');
    expect(article.createdBy).toBe('alice');
    const comment = (await client.queries.fetchNode({ id: 'c1' })).node as Json;
    expect(comment.createdBy).toBe('bob');
    expect('title' in comment).toBe(false);
    expect((await client.queries.fetchNode({ id: 'nope' })).node).toBeNull();
  });

  it('two queries select different shapes of the same union', async () => {
    const photo = (await client.queries.fetchPhotoParts({ id: 'ph1' })).attachment as Json;
    expect(photo.width).toBe(640);
    expect(photo.url).toBe('http://cdn/1.png');
    const video = (await client.queries.fetchPhotoParts({ id: 'v1' })).attachment as Json;
    expect(video.id).toBe('v1');
    expect('seconds' in video).toBe(false);
    const full = (await client.queries.fetchAttachment({ id: 'ph1' })).attachment;
    expect((full as Photo).width).toBe(640);
  });
});

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

describe('subscriptions', () => {
  it('a union stream emits each member', async () => {
    const ws = new DefaultGraphLinkWsAdapter(WS_URL);
    try {
      const sub = new GraphLinkClient(realHttpAdapter, ws);
      const events = await collect<Json>(3, (onData, onErr) => sub.subscriptions.attachmentAdded(onData, onErr));
      expect(events.map((e) => e.attachmentAdded.__typename)).toEqual(['Photo', 'Video', 'Document']);
    } finally {
      await ws.close();
    }
  }, 15000);

  it('an interface stream emits each implementer', async () => {
    const ws = new DefaultGraphLinkWsAdapter(WS_URL);
    try {
      const sub = new GraphLinkClient(realHttpAdapter, ws);
      const events = await collect<Json>(2, (onData, onErr) => sub.subscriptions.entityPublished(onData, onErr));
      expect(events.map((e) => e.entityPublished.__typename)).toEqual(['Article', 'Comment']);
    } finally {
      await ws.close();
    }
  }, 15000);
});
