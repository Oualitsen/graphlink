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
