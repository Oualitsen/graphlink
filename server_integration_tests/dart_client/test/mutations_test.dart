import 'package:test/test.dart';
import 'package:graphlink_server_integration_tests_dart_client/generated/graphlink.dart';
import 'fixtures.dart';

void main() {
  late GraphLinkClient client;
  setUp(() => client = newClient());

  group('createArticle', () {
    test('returns the created article with given input', () async {
      final res = await client.mutations.createArticle(
        input: const CreateArticleInput(title: 'New Post', authorId: '2'),
      );
      expect(res.createArticle.title, equals('New Post'));
      expect(res.createArticle.authorId, equals('2'));
      expect(res.createArticle.id, isNotEmpty);
    });
  });

  group('updateArticle', () {
    test('updates the title and returns the article', () async {
      final created = await client.mutations.createArticle(
        input: const CreateArticleInput(title: 'Original Title', authorId: '1'),
      );
      final res = await client.mutations.updateArticle(
        input: UpdateArticleInput(id: created.createArticle.id, title: 'Updated Title'),
      );
      expect(res.updateArticle.id, equals(created.createArticle.id));
      expect(res.updateArticle.title, equals('Updated Title'));
    });
  });

  group('deleteArticle', () {
    test('returns true when article exists', () async {
      final created = await client.mutations.createArticle(
        input: const CreateArticleInput(title: 'To Delete', authorId: '1'),
      );
      final res = await client.mutations.deleteArticle(id: created.createArticle.id);
      expect(res.deleteArticle, isTrue);
    });

    test('returns false when article does not exist', () async {
      final res = await client.mutations.deleteArticle(id: 'missing-id');
      expect(res.deleteArticle, isFalse);
    });
  });
}
