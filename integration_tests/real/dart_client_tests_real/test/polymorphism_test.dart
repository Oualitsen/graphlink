import 'package:graphlink_client_integration_tests/generated/graphlink.dart';
import 'package:test/test.dart';

import 'real_server_adapter.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('union results', () {
    test('a union member per id', () async {
      final photo = (await client.queries.attachment(id: 'ph1')).attachment;
      final video = (await client.queries.attachment(id: 'v1')).attachment;
      final document = (await client.queries.attachment(id: 'd1')).attachment;
      expect(photo, isA<Photo>());
      expect((photo as Photo).width, 640);
      expect((video as Video).seconds, 30);
      expect((document as Document).pages, 12);
    });

    test('a nullable union decodes null', () async {
      expect((await client.queries.attachment(id: 'nope')).attachment, isNull);
    });

    test('a list of union members', () async {
      final list = (await client.queries.attachments()).attachments;
      expect(list.map((a) => a.runtimeType), [Photo, Video, Document]);
    });

    test('null elements in a list of unions', () async {
      final list = (await client.queries.attachmentsNullable()).attachmentsNullable!;
      expect(list, hasLength(3));
      expect(list[0], isA<Photo>());
      expect(list[1], isNull);
      expect(list[2], isA<Document>());
    });

    test('a union returned by a mutation', () async {
      for (final entry in {'photo': Photo, 'video': Video, 'document': Document}.entries) {
        final created = (await client.mutations.addAttachment(articleId: 'a1', url: 'u', kind: entry.key)).addAttachment;
        expect(created.runtimeType, entry.value, reason: entry.key);
      }
    });

    test('a server error on a union mutation throws', () async {
      await expectLater(client.mutations.addAttachment(articleId: 'a1', url: 'u', kind: 'bogus'), throwsA(anything));
    });
  });

  group('interface results', () {
    test('a list of an interface implementing another interface', () async {
      final feed = (await client.queries.feed()).feed;
      expect(feed.map((e) => e.runtimeType), [Article, Comment, Article, Comment]);
      expect(feed.map((e) => e.createdBy), ['alice', 'bob', 'bob', 'alice']);
    });

    test('a nullable interface returns each implementation or null', () async {
      expect((await client.queries.node(id: 'a1')).node, isA<Article>());
      expect((await client.queries.node(id: 'c1')).node, isA<Comment>());
      expect((await client.queries.node(id: 'zzz')).node, isNull);
    });
  });

  group('nesting', () {
    test('a union field and a list of unions inside an object', () async {
      final article = (await client.queries.article(id: 'a1')).article;
      expect(article.cover, isA<Photo>());
      expect(article.attachments.map((a) => a.runtimeType), [Photo, Video, Document]);
    });

    test('null polymorphic fields', () async {
      final article = (await client.queries.article(id: 'a2')).article;
      expect(article.cover, isNull);
      expect(article.attachments, isEmpty);
      expect(article.related, isNull);
    });

    test('null elements in a list of interfaces', () async {
      final related = (await client.queries.article(id: 'a1')).article.related!;
      expect(related, hasLength(2));
      expect(related[0], isA<Comment>());
      expect(related[1], isNull);
    });

    test('an interface field pointing back at an implementer', () async {
      final feed = (await client.queries.feed()).feed;
      final reply = feed[3] as Comment;
      expect(reply.parent, isA<Article>());
      expect((reply.parent as Article).title, 'Hello');
    });
  });

  group('errors and caching', () {
    test('an unknown article is an error', () async {
      await expectLater(client.queries.article(id: 'zzz'), throwsA(anything));
    });

    test('captured errors on a union operation', () async {
      final ok = await client.queries.attachmentOrErrors(id: 'ph1');
      expect(ok.errors, isNull);
      expect(ok.data!.attachmentOrErrors, isA<Photo>());
      final failed = await client.queries.attachmentOrErrors(id: 'boom');
      expect(failed.data!.attachmentOrErrors, isNull);
      expect(failed.errors!.first.message, isNotEmpty);
    });

    test('a cached union operation is served once', () async {
      var calls = 0;
      final real = httpAdapterForPort(9999);
      final counting = GraphLinkClient(
        adapter: (payload) {
          calls++;
          return real(payload);
        },
        wsAdapter: DefaultGraphLinkWebSocketAdapter(url: 'ws://localhost:9999/graphql'),
      );
      final first = (await counting.queries.getCachedAttachment(id: 'v1')).getCachedAttachment;
      final second = (await counting.queries.getCachedAttachment(id: 'v1')).getCachedAttachment;
      expect(first, isA<Video>());
      expect(second, isA<Video>());
      expect(calls, 1);
    });
  });

  group('custom queries', () {
    test('inline fragments on every member of a union', () async {
      final photo = (await client.queries.fetchAttachment(id: 'ph1')).attachment;
      final video = (await client.queries.fetchAttachment(id: 'v1')).attachment;
      final document = (await client.queries.fetchAttachment(id: 'd1')).attachment;
      expect((photo as Photo).width, 640);
      expect((video as Video).seconds, 30);
      expect((document as Document).pages, 12);
      expect((await client.queries.fetchAttachment(id: 'nope')).attachment, isNull);
    });

    test('one fragment shared by two root fields', () async {
      final res = await client.queries.fetchArticleAndAttachment(articleId: 'a1', attachmentId: 'v1');
      expect(res.article.cover!.toJson()['__typename'], 'Photo');
      expect(res.attachment!.toJson()['__typename'], 'Video');
    });
  });

  group('selections of one abstract type that differ between queries', () {
    test('an interface selection with inline fragments and a shared fragment', () async {
      final feed = (await client.queries.fetchFeed()).feed.map((e) => e.toJson()).toList();
      expect(feed.map((e) => e['__typename']), ['Article', 'Comment', 'Article', 'Comment']);
      expect(feed[0]['title'], 'Hello');
      expect((feed[0]['cover'] as Map)['url'], 'http://cdn/1.png');
      expect((feed[0]['attachments'] as List).map((a) => (a as Map)['id']), ['ph1', 'v1', 'd1']);
      expect(feed[1]['text'], 'Nice');
      expect(feed[2]['cover'], isNull);
    });

    test('an interface selection that names only some implementers', () async {
      final article = (await client.queries.fetchNode(id: 'a1')).node!.toJson();
      expect(article['title'], 'Hello');
      expect(article['createdBy'], 'alice');
      final comment = (await client.queries.fetchNode(id: 'c1')).node!.toJson();
      expect(comment['createdBy'], 'bob');
      expect(comment.containsKey('title'), isFalse);
      expect((await client.queries.fetchNode(id: 'nope')).node, isNull);
    });

    test('two queries select different shapes of the same union', () async {
      final photo = (await client.queries.fetchPhotoParts(id: 'ph1')).attachment!.toJson();
      expect(photo['width'], 640);
      expect(photo['url'], 'http://cdn/1.png');
      final video = (await client.queries.fetchPhotoParts(id: 'v1')).attachment!.toJson();
      expect(video['id'], 'v1');
      expect(video.containsKey('seconds'), isFalse);
      final full = (await client.queries.fetchAttachment(id: 'ph1')).attachment;
      expect((full as Photo).width, 640);
    });
  });

  group('members with the same field under different types', () {
    test('an alias keeps both types readable', () async {
      final phone = (await client.queries.fetchGadget(id: 'p1')).gadget as Phone_IdSize;
      final laptop = (await client.queries.fetchGadget(id: 'l1')).gadget as Laptop_IdSize;
      expect(phone.size, 6);
      expect(laptop.laptopSize, '15 inch');
      expect((await client.queries.fetchGadget(id: 'nope')).gadget, isNull);
    });

    test('a list of both members', () async {
      final gadgets = (await client.queries.fetchGadgets()).gadgets;
      expect(gadgets.map((g) => g.runtimeType), [Phone_IdSize, Laptop_IdSize]);
    });
  });

  group('a type that belongs to two unions', () {
    test('Photo decodes through Shareable and through Attachment', () async {
      expect((await client.queries.shareable(id: 'ph1')).shareable, isA<Photo>());
      expect((await client.queries.attachment(id: 'ph1')).attachment, isA<Photo>());
    });

    test('Phone decodes through Shareable', () async {
      final shareable = (await client.queries.shareable(id: 'p1')).shareable;
      expect(shareable, isA<Phone>());
      expect((shareable as Phone).model, 'Pixel');
      expect((await client.queries.shareable(id: 'nope')).shareable, isNull);
    });
  });

  group('an interface with a field argument and a self reference', () {
    test('the argument reaches every implementer and each keeps its own fields', () async {
      final album = (await client.queries.listing(id: 'al1', fieldArgs: const ListingFieldArgs(itemsLimit: 2))).listing;
      expect(album, isA<Album>());
      expect((album as Album).year, 2020);
      expect(album.items.map((a) => a.runtimeType), [Photo, Video]);
      final playlist = (await client.queries.listing(id: 'pl1', fieldArgs: const ListingFieldArgs(itemsLimit: 5))).listing;
      expect((playlist as Playlist).tracks, 12);
      expect(playlist.items.map((a) => a.runtimeType), [Video, Document]);
    });

    test('a limit of zero yields empty lists', () async {
      final album = (await client.queries.listing(id: 'al1', fieldArgs: const ListingFieldArgs(itemsLimit: 0))).listing!;
      expect(album.items, isEmpty);
    });

    test('the interface field returns the other implementer, or null', () async {
      final album = (await client.queries.listing(id: 'al1', fieldArgs: const ListingFieldArgs(itemsLimit: 1))).listing!;
      expect(album.related, isA<Playlist>());
      expect((album.related as Playlist).tracks, 12);
      final winter = (await client.queries.listing(id: 'al2', fieldArgs: const ListingFieldArgs(itemsLimit: 1))).listing!;
      expect(winter.related, isNull);
    });

    test('an unknown id decodes null', () async {
      final response = await client.queries.listing(id: 'nope', fieldArgs: const ListingFieldArgs(itemsLimit: 1));
      expect(response.listing, isNull);
    });

    test('a list of the interface decodes each implementer', () async {
      final list = (await client.queries.listings(fieldArgs: const ListingsFieldArgs(itemsLimit: 1))).listings;
      expect(list.map((l) => l.runtimeType), [Album, Playlist, Album]);
      expect(list.map((l) => l.items.length), [1, 1, 1]);
    });
  });

  group('a union with a single member', () {
    test('decodes to the member', () async {
      final solo = (await client.queries.solo(fieldArgs: const SoloFieldArgs(itemsLimit: 1))).solo;
      expect(solo, isA<Album>());
      expect((solo as Album).title, 'Summer');
    });
  });

  group('members that share a field with the same type', () {
    test('id and url are readable on the union itself', () async {
      final list = (await client.queries.attachments()).attachments;
      expect(list.map((a) => a.id), ['ph1', 'v1', 'd1']);
      expect(list.map((a) => a.url), ['http://cdn/1.png', 'http://cdn/1.mp4', 'http://cdn/1.pdf']);
    });

    test('a selection that shares only some fields exposes just those', () async {
      expect((await client.queries.fetchPhotoParts(id: 'ph1')).attachment!.id, 'ph1');
      expect((await client.queries.fetchPhotoParts(id: 'v1')).attachment!.id, 'v1');
    });

    test('a union of two types shares only id', () async {
      expect((await client.queries.shareable(id: 'ph1')).shareable!.id, 'ph1');
      expect((await client.queries.shareable(id: 'p1')).shareable!.id, 'p1');
    });
  });

  group('a member returned directly and projected in the same client', () {
    test('the direct query keeps the full type', () async {
      final photo = (await client.queries.photo(id: 'ph1')).photo!;
      expect([photo.id, photo.url, photo.width], ['ph1', 'http://cdn/1.png', 640]);
      expect((await client.queries.photo(id: 'nope')).photo, isNull);
    });

    test('a partial selection of the same type does not replace it', () async {
      expect((await client.queries.fetchPhotoWidth(id: 'ph1')).photo!.width, 640);
      final member = (await client.queries.fetchPhotoUrl(id: 'ph1')).attachment;
      expect((member as Photo_Url).url, 'http://cdn/1.png');
      expect((await client.queries.fetchPhotoUrl(id: 'v1')).attachment, isA<Video_Id>());
    });
  });

  group('an inline fragment on the interface mixed with concrete ones', () {
    test('the interface fields reach every member and the concrete ones their own', () async {
      final list = (await client.queries.searchMixed(term: 'x')).search;
      expect(list.map((r) => r.id), ['user-1', 'post-1']);
      expect((list[0] as UserResult_IdName).name, 'Alice Smith');
      expect((list[1] as PostResult).title, 'Hello World');
    });
  });

  group('cached polymorphic operations and tag invalidation', () {
    Future<String> nodeTitle() async => ((await client.queries.getCachedNode(id: 'a1')).getCachedNode as Article).title;
    Future<int> videoSeconds() async => ((await client.queries.getCachedAttachment(id: 'v1')).getCachedAttachment as Video).seconds;

    test('a cached interface result is served from the cache', () async {
      expect(await nodeTitle(), await nodeTitle());
    });

    test('invalidating the tag of a cached interface fetches it again', () async {
      final before = await nodeTitle();
      await client.mutations.evictNodes();
      expect(await nodeTitle(), isNot(before));
    });

    test('invalidating the tag of a cached union fetches it again', () async {
      final before = await videoSeconds();
      expect(await videoSeconds(), before);
      await client.mutations.evictAttachments();
      expect(await videoSeconds(), isNot(before));
    });

    test('invalidating another tag leaves the cached union alone', () async {
      final before = await videoSeconds();
      await client.mutations.evictNodes();
      expect(await videoSeconds(), before);
    });
  });

  group('subscriptions', () {
    test('a union stream emits each member', () async {
      final events = await client.subscriptions.attachmentAdded().take(3).toList().timeout(const Duration(seconds: 10));
      expect(events.map((e) => e.attachmentAdded.runtimeType), [Photo, Video, Document]);
    });

    test('an interface stream emits each implementer', () async {
      final events = await client.subscriptions.entityPublished().take(2).toList().timeout(const Duration(seconds: 10));
      expect(events.map((e) => e.entityPublished.runtimeType), [Article, Comment]);
    });
  });
}
