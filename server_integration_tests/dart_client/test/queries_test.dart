import 'package:test/test.dart';
import 'package:graphlink_server_integration_tests_dart_client/generated/graphlink.dart';
import 'fixtures.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('getAuthor', () {
    test('returns author by id', () async {
      final res = await client.queries.getAuthor(id: '1');
      expect(res.getAuthor, isNotNull);
      expect(res.getAuthor!.id, equals('1'));
      expect(res.getAuthor!.name, equals('Ramdane'));
    });

    test('returns null for unknown id', () async {
      final res = await client.queries.getAuthor(id: 'missing');
      expect(res.getAuthor, isNull);
    });

    test('articles is resolved via batch DataLoader mapping', () async {
      final res = await client.queries.getAuthor(id: '1');
      final titles = res.getAuthor!.articles.map((a) => a.title).toSet();
      expect(titles, containsAll(['GraphLink Basics', 'Advanced GraphLink']));
    });
  });

  group('getArticle', () {
    test('returns article by id', () async {
      final res = await client.queries.getArticle(id: '1');
      expect(res.getArticle.id, equals('1'));
      expect(res.getArticle.title, equals('GraphLink Basics'));
    });

    test('author is resolved via non-batch schema mapping', () async {
      final res = await client.queries.getArticle(id: '1');
      expect(res.getArticle.author.id, equals('1'));
      expect(res.getArticle.author.name, equals('Ramdane'));
    });
  });

  group('listAuthors / listArticles', () {
    test('listAuthors returns all authors', () async {
      final res = await client.queries.listAuthors();
      expect(res.listAuthors.map((a) => a.id), containsAll(['1', '2']));
    });

    test('listArticles returns all articles', () async {
      final res = await client.queries.listArticles();
      expect(res.listArticles.map((a) => a.id), contains('1'));
    });
  });
}
