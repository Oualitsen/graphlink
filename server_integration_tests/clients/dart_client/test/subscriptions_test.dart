import 'package:test/test.dart';
import 'package:graphlink_server_integration_tests_dart_client/generated/graphlink.dart';
import 'fixtures.dart';

void main() {
  group('articleCreated', () {
    test('emits when an article is created', () async {
      final client = newClient();
      try {
        
        final eventFuture = client.subscriptions
            .articleCreated(
              fieldArgs: const ArticleCreatedFieldArgs(latestArticlesLimit: 2)
            )
            .first
            .timeout(const Duration(seconds: 10));

        // give the subscription a moment to register before triggering the mutation
        await Future.delayed(const Duration(milliseconds: 300));

        final created = await client.mutations.createArticle(
          input: const CreateArticleInput(title: 'Subscribed Post', authorId: '1'),
          fieldArgs: const CreateArticleFieldArgs(latestArticlesLimit: 2)
        );

        final event = await eventFuture;
        expect(event.articleCreated.id, equals(created.createArticle.id));
        expect(event.articleCreated.title, equals('Subscribed Post'));
      } finally{}
    });
  });

  group('articleUpdated', () {
    test('emits when the matching article is updated', () async {
      final client = newClient();
      try {
        final created = await client.mutations.createArticle(
          input: const CreateArticleInput(title: 'Will Update', authorId: '2'),
          fieldArgs: const CreateArticleFieldArgs(latestArticlesLimit: 2)
        );

        final eventFuture = client.subscriptions
            .articleUpdated(id: created.createArticle.id,
            fieldArgs: const ArticleUpdatedFieldArgs(latestArticlesLimit: 2)
            )
            .first
            .timeout(const Duration(seconds: 10));

        await Future.delayed(const Duration(milliseconds: 300));

        final updated = await client.mutations.updateArticle(
          input: UpdateArticleInput(id: created.createArticle.id, title: 'Updated via subscription'),
          fieldArgs: const UpdateArticleFieldArgs(latestArticlesLimit: 2)
        );

        final event = await eventFuture;
        expect(event.articleUpdated.id, equals(updated.updateArticle.id));
        expect(event.articleUpdated.title, equals('Updated via subscription'));
      } finally {
      }
    });
  });
}
