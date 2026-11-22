import unittest

from generated import MappedArticle, MappedArticleDraftInput


class TypeWithSeveralTargets(unittest.TestCase):
    def setUp(self) -> None:
        self.article = MappedArticle(id="a1", title="Hello", body="Body text", views=7)
        self.unviewed = MappedArticle(id="a2", title="Quiet", body="No readers", views=None)

    def test_summary_renames_title_to_headline(self) -> None:
        summary = self.article.to_mapped_article_summary()
        self.assertEqual(summary.id, "a1")
        self.assertEqual(summary.headline, "Hello")

    def test_card_renames_title_to_name_and_keeps_views(self) -> None:
        card = self.article.to_mapped_article_card(default_views=99)
        self.assertEqual(card.id, "a1")
        self.assertEqual(card.name, "Hello")
        self.assertEqual(card.views, 7)

    def test_card_uses_default_views_when_views_is_none(self) -> None:
        card = self.unviewed.to_mapped_article_card(default_views=99)
        self.assertEqual(card.name, "Quiet")
        self.assertEqual(card.views, 99)

    def test_update_input_keeps_title_and_takes_status(self) -> None:
        update = self.article.to_mapped_article_update_input(status="PUBLISHED")
        self.assertEqual(update.id, "a1")
        self.assertEqual(update.title, "Hello")
        self.assertEqual(update.body, "Body text")
        self.assertEqual(update.status, "PUBLISHED")

    def test_every_mapping_returns_a_new_object(self) -> None:
        self.assertIsNot(self.article.to_mapped_article_summary(), self.article)


class InputWithSeveralTargets(unittest.TestCase):
    def setUp(self) -> None:
        self.draft = MappedArticleDraftInput(title="Draft", body="Text", views=3)
        self.bare = MappedArticleDraftInput(title="Bare", body="Nothing", views=None)

    def test_to_mapped_article_copies_the_fields_and_takes_id(self) -> None:
        mapped = self.draft.to_mapped_article(id="d1")
        self.assertEqual(mapped.id, "d1")
        self.assertEqual(mapped.title, "Draft")
        self.assertEqual(mapped.body, "Text")
        self.assertEqual(mapped.views, 3)

    def test_to_mapped_article_keeps_a_none_views(self) -> None:
        self.assertIsNone(self.bare.to_mapped_article(id="d2").views)

    def test_to_update_input_takes_id_and_status(self) -> None:
        update = self.draft.to_mapped_article_update_input(id="d1", status="DRAFT")
        self.assertEqual(update.id, "d1")
        self.assertEqual(update.title, "Draft")
        self.assertEqual(update.body, "Text")
        self.assertEqual(update.status, "DRAFT")
