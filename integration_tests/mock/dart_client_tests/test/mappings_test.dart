import 'package:test/test.dart';
import 'package:graphlink_client_integration_tests/generated/inputs/mapped_article_draft_input.dart';
import 'package:graphlink_client_integration_tests/generated/types/mapped_article.dart';

void main() {
  const article = MappedArticle(id: 'a1', title: 'Hello', body: 'Body text', views: 7);
  const unviewed = MappedArticle(id: 'a2', title: 'Quiet', body: 'No readers');

  group('type with several targets', () {
    test('toMappedArticleSummary renames title to headline', () {
      final summary = article.toMappedArticleSummary();
      expect(summary.id, 'a1');
      expect(summary.headline, 'Hello');
    });

    test('toMappedArticleCard renames title to name and keeps views', () {
      final card = article.toMappedArticleCard(defaultViews: 99);
      expect(card.id, 'a1');
      expect(card.name, 'Hello');
      expect(card.views, 7);
    });

    test('toMappedArticleCard uses defaultViews when views is null', () {
      final card = unviewed.toMappedArticleCard(defaultViews: 99);
      expect(card.name, 'Quiet');
      expect(card.views, 99);
    });

    test('toMappedArticleUpdateInput keeps title and takes status as a parameter', () {
      final update = article.toMappedArticleUpdateInput(status: 'PUBLISHED');
      expect(update.id, 'a1');
      expect(update.title, 'Hello');
      expect(update.body, 'Body text');
      expect(update.status, 'PUBLISHED');
    });

    test('every mapping returns a new object of the target type', () {
      expect(article.toMappedArticleSummary(), isNot(same(article)));
    });
  });

  group('input with several targets', () {
    const draft = MappedArticleDraftInput(title: 'Draft', body: 'Text', views: 3);
    const bare = MappedArticleDraftInput(title: 'Bare', body: 'Nothing');

    test('toMappedArticle copies the fields and takes id as a parameter', () {
      final mapped = draft.toMappedArticle(id: 'd1');
      expect(mapped.id, 'd1');
      expect(mapped.title, 'Draft');
      expect(mapped.body, 'Text');
      expect(mapped.views, 3);
    });

    test('toMappedArticle keeps a null views', () {
      expect(bare.toMappedArticle(id: 'd2').views, isNull);
    });

    test('toMappedArticleUpdateInput takes id and status as parameters', () {
      final update = draft.toMappedArticleUpdateInput(id: 'd1', status: 'DRAFT');
      expect(update.id, 'd1');
      expect(update.title, 'Draft');
      expect(update.body, 'Text');
      expect(update.status, 'DRAFT');
    });
  });
}
