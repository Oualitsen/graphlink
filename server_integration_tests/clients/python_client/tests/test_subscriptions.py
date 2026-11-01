import unittest

from generated import (
    ArticleCreatedFieldArgs,
    ArticleUpdatedFieldArgs,
    CreateArticleFieldArgs,
    CreateArticleInput,
    UpdateArticleFieldArgs,
    UpdateArticleInput,
)

from .fixtures import new_client, start_first


class SubscriptionsTest(unittest.IsolatedAsyncioTestCase):
    async def test_article_created_emits_when_an_article_is_created(self) -> None:
        client = new_client()
        event = await start_first(client.subscriptions.article_created(field_args=ArticleCreatedFieldArgs(latest_articles_limit=2)))
        created = await client.mutations.create_article(
            input=CreateArticleInput(title="Subscribed Post", author_id="1"),
            field_args=CreateArticleFieldArgs(latest_articles_limit=2),
        )
        received = (await event).article_created
        self.assertEqual((received.id, received.title), (created.create_article.id, "Subscribed Post"))

    async def test_article_updated_emits_when_the_matching_article_is_updated(self) -> None:
        client = new_client()
        created = await client.mutations.create_article(
            input=CreateArticleInput(title="Will Update", author_id="2"),
            field_args=CreateArticleFieldArgs(latest_articles_limit=2),
        )
        event = await start_first(
            client.subscriptions.article_updated(id=created.create_article.id, field_args=ArticleUpdatedFieldArgs(latest_articles_limit=2))
        )
        updated = await client.mutations.update_article(
            input=UpdateArticleInput(id=created.create_article.id, title="Updated via subscription"),
            field_args=UpdateArticleFieldArgs(latest_articles_limit=2),
        )
        received = (await event).article_updated
        self.assertEqual((received.id, received.title), (updated.update_article.id, "Updated via subscription"))
