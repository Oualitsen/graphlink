import { beforeEach, describe, expect, it } from 'vitest';
import { GraphLinkClient } from '../lib/generated/client/graph-link-client.js';
import type { Album, Article, Comment, Document, Photo, Playlist, Video } from '../lib/generated/graphlink.js';
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

describe('members with the same field under different types', () => {
  it('an alias keeps both types readable', async () => {
    const phone = (await client.queries.fetchGadget({ id: 'p1' })).gadget as Json;
    const laptop = (await client.queries.fetchGadget({ id: 'l1' })).gadget as Json;
    expect(phone.__typename).toBe('Phone');
    expect(phone.size).toBe(6);
    expect(laptop.__typename).toBe('Laptop');
    expect(laptop.laptopSize).toBe('15 inch');
    expect((await client.queries.fetchGadget({ id: 'nope' })).gadget).toBeNull();
  });

  it('a list of both members', async () => {
    const gadgets = (await client.queries.fetchGadgets()).gadgets as Json[];
    expect(gadgets.map((g) => g.__typename)).toEqual(['Phone', 'Laptop']);
  });
});

describe('a type that belongs to two unions', () => {
  it('Photo decodes through Shareable and through Attachment', async () => {
    expect((await client.queries.shareable({ id: 'ph1' })).shareable!.__typename).toBe('Photo');
    expect((await client.queries.attachment({ id: 'ph1' })).attachment!.__typename).toBe('Photo');
  });

  it('Phone decodes through Shareable', async () => {
    const shareable = (await client.queries.shareable({ id: 'p1' })).shareable as Json;
    expect(shareable.__typename).toBe('Phone');
    expect(shareable.model).toBe('Pixel');
    expect((await client.queries.shareable({ id: 'nope' })).shareable).toBeNull();
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

describe('an interface with a field argument and a self reference', () => {
  it('the argument reaches every implementer and each keeps its own fields', async () => {
    const album = (await client.queries.listing({ id: 'al1', fieldArgs: { itemsLimit: 2 } })).listing as Album;
    expect(album.__typename).toBe('Album');
    expect(album.year).toBe(2020);
    expect(kinds(album.items)).toEqual(['Photo', 'Video']);
    const playlist = (await client.queries.listing({ id: 'pl1', fieldArgs: { itemsLimit: 5 } })).listing as Playlist;
    expect(playlist.tracks).toBe(12);
    expect(kinds(playlist.items)).toEqual(['Video', 'Document']);
  });

  it('a limit of zero yields empty lists', async () => {
    const album = (await client.queries.listing({ id: 'al1', fieldArgs: { itemsLimit: 0 } })).listing;
    expect(album!.items).toEqual([]);
  });

  it('the interface field returns the other implementer, or null', async () => {
    const album = (await client.queries.listing({ id: 'al1', fieldArgs: { itemsLimit: 1 } })).listing;
    expect(album!.related!.__typename).toBe('Playlist');
    expect((album!.related as Playlist).tracks).toBe(12);
    const winter = (await client.queries.listing({ id: 'al2', fieldArgs: { itemsLimit: 1 } })).listing;
    expect(winter!.related).toBeNull();
  });

  it('an unknown id decodes null', async () => {
    expect((await client.queries.listing({ id: 'nope', fieldArgs: { itemsLimit: 1 } })).listing).toBeNull();
  });

  it('a list of the interface decodes each implementer', async () => {
    const list = (await client.queries.listings({ fieldArgs: { itemsLimit: 1 } })).listings;
    expect(kinds(list)).toEqual(['Album', 'Playlist', 'Album']);
    expect(list.map((l) => l.items.length)).toEqual([1, 1, 1]);
  });
});

describe('a union with a single member', () => {
  it('decodes to the member', async () => {
    const solo = (await client.queries.solo({ fieldArgs: { itemsLimit: 1 } })).solo as Album;
    expect(solo.__typename).toBe('Album');
    expect(solo.title).toBe('Summer');
  });
});

describe('members that share a field with the same type', () => {
  it('id and url are readable on the union itself', async () => {
    const list = (await client.queries.attachments()).attachments;
    expect(list.map((a) => a.id)).toEqual(['ph1', 'v1', 'd1']);
    expect(list.map((a) => a.url)).toEqual(['http://cdn/1.png', 'http://cdn/1.mp4', 'http://cdn/1.pdf']);
  });

  it('a selection that shares only some fields exposes just those', async () => {
    expect((await client.queries.fetchPhotoParts({ id: 'ph1' })).attachment!.id).toBe('ph1');
    expect((await client.queries.fetchPhotoParts({ id: 'v1' })).attachment!.id).toBe('v1');
  });

  it('a union of two types shares only id', async () => {
    expect((await client.queries.shareable({ id: 'ph1' })).shareable!.id).toBe('ph1');
    expect((await client.queries.shareable({ id: 'p1' })).shareable!.id).toBe('p1');
  });
});

describe('a member returned directly and projected in the same client', () => {
  it('the direct query keeps the full type', async () => {
    const photo = (await client.queries.photo({ id: 'ph1' })).photo!;
    expect([photo.id, photo.url, photo.width]).toEqual(['ph1', 'http://cdn/1.png', 640]);
    expect((await client.queries.photo({ id: 'nope' })).photo).toBeNull();
  });

  it('a partial selection of the same type does not replace it', async () => {
    expect((await client.queries.fetchPhotoWidth({ id: 'ph1' })).photo!.width).toBe(640);
    const member = (await client.queries.fetchPhotoUrl({ id: 'ph1' })).attachment as Json;
    expect(member).toMatchObject({ __typename: 'Photo', url: 'http://cdn/1.png' });
    expect((await client.queries.fetchPhotoUrl({ id: 'v1' })).attachment).toMatchObject({ __typename: 'Video', id: 'v1' });
  });
});

describe('an inline fragment on the interface mixed with concrete ones', () => {
  it('the interface fields reach every member and the concrete ones their own', async () => {
    const list = (await client.queries.searchMixed({ term: 'x' })).search as Json[];
    expect(list.map((r) => r.id)).toEqual(['user-1', 'post-1']);
    expect(list[0]).toMatchObject({ __typename: 'UserResult', name: 'Alice Smith' });
    expect(list[1]).toMatchObject({ __typename: 'PostResult', title: 'Hello World' });
  });
});

describe('cached polymorphic operations and tag invalidation', () => {
  const nodeTitle = async () => ((await client.queries.getCachedNode({ id: 'a1' })).getCachedNode as Article).title;
  const videoSeconds = async () => ((await client.queries.getCachedAttachment({ id: 'v1' })).getCachedAttachment as Video).seconds;

  it('a cached interface result is served from the cache', async () => {
    expect(await nodeTitle()).toBe(await nodeTitle());
  });

  it('invalidating the tag of a cached interface fetches it again', async () => {
    const before = await nodeTitle();
    await client.mutations.evictNodes();
    expect(await nodeTitle()).not.toBe(before);
  });

  it('invalidating the tag of a cached union fetches it again', async () => {
    const before = await videoSeconds();
    expect(await videoSeconds()).toBe(before);
    await client.mutations.evictAttachments();
    expect(await videoSeconds()).not.toBe(before);
  });

  it('invalidating another tag leaves the cached union alone', async () => {
    const before = await videoSeconds();
    await client.mutations.evictNodes();
    expect(await videoSeconds()).toBe(before);
  });
});

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
