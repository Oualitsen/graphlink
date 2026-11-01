import unittest

from generated import GetAuthorAndArticleFieldArgs, GetAuthorFieldArgs, GetArticleFieldArgs, ListArticlesFieldArgs, ListAuthorsFieldArgs

from .fixtures import new_client


class QueriesTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()

    async def test_get_author_returns_author_by_id(self) -> None:
        res = await self.client.queries.get_author(id="1", field_args=GetAuthorFieldArgs(latest_articles_limit=10))
        self.assertEqual((res.get_author.id, res.get_author.name), ("1", "Ramdane"))

    async def test_get_author_returns_null_for_unknown_id(self) -> None:
        res = await self.client.queries.get_author(id="missing", field_args=GetAuthorFieldArgs(latest_articles_limit=10))
        self.assertIsNone(res.get_author)

    async def test_articles_resolved_via_batch_data_loader_mapping(self) -> None:
        res = await self.client.queries.get_author(id="1", field_args=GetAuthorFieldArgs(latest_articles_limit=10))
        titles = {a.title for a in res.get_author.articles}
        self.assertTrue({"GraphLink Basics", "Advanced GraphLink"} <= titles)

    async def test_latest_articles_resolved_via_non_batch_mapping_with_arguments(self) -> None:
        res = await self.client.queries.get_author(id="1", field_args=GetAuthorFieldArgs(latest_articles_limit=10))
        titles = {a.title for a in res.get_author.latest_articles}
        self.assertTrue({"GraphLink Basics", "Advanced GraphLink"} <= titles)

    async def test_get_author_without_article_does_not_require_limit_argument(self) -> None:
        res = await self.client.queries.get_author_without_article(id="1")
        self.assertEqual((res.get_author.id, res.get_author.name), ("1", "Ramdane"))

    async def test_get_article_returns_article_by_id(self) -> None:
        res = await self.client.queries.get_article(id="1", field_args=GetArticleFieldArgs(latest_articles_limit=2))
        self.assertEqual((res.get_article.id, res.get_article.title), ("1", "GraphLink Basics"))

    async def test_get_article_author_resolved_via_non_batch_schema_mapping(self) -> None:
        res = await self.client.queries.get_article(id="1", field_args=GetArticleFieldArgs(latest_articles_limit=2))
        self.assertEqual((res.get_article.author.id, res.get_article.author.name), ("1", "Ramdane"))

    async def test_get_author_and_article_resolves_both_root_fields(self) -> None:
        res = await self.client.queries.get_author_and_article(
            author_id="1", article_id="3", field_args=GetAuthorAndArticleFieldArgs(latest_articles_limit=1)
        )
        self.assertEqual(res.author.id, "1")
        self.assertEqual(len(res.author.latest_articles), 1)
        self.assertEqual((res.article.id, res.article.title), ("3", "Alice's First Post"))

    async def test_list_authors_returns_all_authors(self) -> None:
        res = await self.client.queries.list_authors(field_args=ListAuthorsFieldArgs(latest_articles_limit=10))
        self.assertTrue({"1", "2"} <= {a.id for a in res.list_authors})

    async def test_list_articles_returns_all_articles(self) -> None:
        res = await self.client.queries.list_articles(field_args=ListArticlesFieldArgs(latest_articles_limit=2))
        self.assertIn("1", [a.id for a in res.list_articles])
