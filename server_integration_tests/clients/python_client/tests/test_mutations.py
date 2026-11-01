import unittest

from generated import CreateArticleFieldArgs, CreateArticleInput, Priority, UpdateArticleFieldArgs, UpdateArticleInput

from .fixtures import new_client

ARGS = CreateArticleFieldArgs(latest_articles_limit=2)


class MutationsTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()

    async def test_create_article_returns_created_article_with_given_input(self) -> None:
        res = await self.client.mutations.create_article(input=CreateArticleInput(title="New Post", author_id="2"), field_args=ARGS)
        self.assertEqual((res.create_article.title, res.create_article.author_id), ("New Post", "2"))
        self.assertTrue(res.create_article.id)

    async def test_update_article_updates_title_and_returns_article(self) -> None:
        created = await self.client.mutations.create_article(input=CreateArticleInput(title="Original Title", author_id="1"), field_args=ARGS)
        res = await self.client.mutations.update_article(
            input=UpdateArticleInput(id=created.create_article.id, title="Updated Title"),
            field_args=UpdateArticleFieldArgs(latest_articles_limit=2),
        )
        self.assertEqual((res.update_article.id, res.update_article.title), (created.create_article.id, "Updated Title"))

    async def test_delete_article_returns_true_when_article_exists(self) -> None:
        created = await self.client.mutations.create_article(input=CreateArticleInput(title="To Delete", author_id="1"), field_args=ARGS)
        self.assertTrue((await self.client.mutations.delete_article(id=created.create_article.id)).delete_article)

    async def test_delete_article_returns_false_when_article_does_not_exist(self) -> None:
        self.assertFalse((await self.client.mutations.delete_article(id="missing-id")).delete_article)

    async def test_ack_priority_enum_mutation_argument(self) -> None:
        self.assertEqual((await self.client.mutations.ack_priority(level=Priority.HIGH)).ack_priority, "OK")
