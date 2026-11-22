import unittest
from typing import Any, Awaitable, Callable

from generated import (
    ArticleInput,
    ArticleNotFound,
    Banned,
    Forbidden,
    GraphLinkClient,
    GraphLinkDomainError,
    GraphLinkException,
    Reason,
    TitleTaken,
)

URL = "http://127.0.0.1:9930/graphql"


class TypedErrorsTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = GraphLinkClient.with_http(url=URL)

    async def thrown_by(self, call: Callable[[], Awaitable[Any]]) -> BaseException:
        try:
            await call()
        except BaseException as e:
            return e
        self.fail("expected an exception")

    async def test_a_successful_call_returns_its_data(self) -> None:
        res = await self.client.queries.article(id="1")
        self.assertEqual(res.article.id, "1")

    async def test_a_declared_error_is_thrown_as_its_class_with_its_fields(self) -> None:
        e = await self.thrown_by(lambda: self.client.queries.article(id="missing"))
        self.assertIsInstance(e, ArticleNotFound)
        self.assertIsInstance(e, GraphLinkDomainError)
        self.assertEqual(e.id, "missing")
        self.assertEqual(e.message, "Article missing not found")

    async def test_it_can_be_caught_by_type(self) -> None:
        caught = ""
        try:
            await self.client.queries.article(id="missing")
        except ArticleNotFound as e:
            caught = e.id
        self.assertEqual(caught, "missing")

    async def test_an_error_matched_on_a_custom_field_and_value(self) -> None:
        e = await self.thrown_by(lambda: self.client.queries.article(id="forbidden"))
        self.assertIsInstance(e, Forbidden)
        self.assertEqual(e.message, "No access")

    async def test_an_error_of_another_root_field(self) -> None:
        e = await self.thrown_by(lambda: self.client.queries.secret())
        self.assertIsInstance(e, Forbidden)

    async def test_an_unknown_code_keeps_graph_link_exception(self) -> None:
        e = await self.thrown_by(lambda: self.client.queries.article(id="other-code"))
        self.assertIsInstance(e, GraphLinkException)
        self.assertEqual(e.errors[0].message, "A new error")

    async def test_a_missing_required_field_falls_back(self) -> None:
        e = await self.thrown_by(lambda: self.client.queries.article(id="no-field"))
        self.assertIsInstance(e, GraphLinkException)

    async def test_an_entry_without_a_path_falls_back(self) -> None:
        e = await self.thrown_by(lambda: self.client.queries.article(id="no-path"))
        self.assertIsInstance(e, GraphLinkException)

    async def test_an_entry_without_extensions_falls_back(self) -> None:
        e = await self.thrown_by(lambda: self.client.queries.article(id="no-extensions"))
        self.assertIsInstance(e, GraphLinkException)

    async def test_an_operation_without_throws_keeps_graph_link_exception(self) -> None:
        e = await self.thrown_by(lambda: self.client.queries.plain(id="1"))
        self.assertIsInstance(e, GraphLinkException)
        self.assertNotIsInstance(e, GraphLinkDomainError)

    async def test_a_combined_query_keeps_graph_link_exception(self) -> None:
        e = await self.thrown_by(lambda: self.client.queries.pair())
        self.assertIsInstance(e, GraphLinkException)
        self.assertEqual(e.errors[0].path, ["first"])

    async def test_a_capture_errors_operation_returns_the_errors(self) -> None:
        res = await self.client.queries.captured()
        self.assertEqual(res.errors[0].extensions["code"], "ArticleNotFound")

    async def test_a_mutation_returns_its_data(self) -> None:
        res = await self.client.mutations.create_article(input=ArticleInput(title="fresh"))
        self.assertEqual(res.create_article.id, "fresh")

    async def test_a_declared_error_carries_a_list_field(self) -> None:
        e = await self.thrown_by(lambda: self.client.mutations.create_article(input=ArticleInput(title="taken")))
        self.assertIsInstance(e, TitleTaken)
        self.assertEqual(e.title, "taken")
        self.assertEqual(e.suggestions, ["taken-2"])

    async def test_an_error_with_its_own_value_an_enum_and_an_optional_field(self) -> None:
        e = await self.thrown_by(lambda: self.client.mutations.create_article(input=ArticleInput(title="banned")))
        self.assertIsInstance(e, Banned)
        self.assertEqual(e.reason, Reason.SPAM)
        self.assertEqual(e.until, 5)
