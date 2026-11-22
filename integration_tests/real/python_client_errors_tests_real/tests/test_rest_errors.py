import unittest
from typing import Any, Awaitable, Callable

from generated import (
    GraphLinkClient,
    GraphLinkDomainError,
    ItemConflict,
    ItemInput,
    ItemNotFound,
    RateLimited,
    RestError,
    Teapot,
)


class RestErrorsTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = GraphLinkClient.with_http(url="http://127.0.0.1:9930/graphql", rest_base_url="http://127.0.0.1:9930")

    async def thrown_by(self, call: Callable[[], Awaitable[Any]]) -> BaseException:
        try:
            await call()
        except BaseException as e:
            return e
        self.fail("expected an exception")

    async def test_a_successful_call_returns_its_data(self) -> None:
        self.assertEqual((await self.client.queries.item(id="1")).name, "Item 1")

    async def test_a_status_only_error_is_thrown_with_the_fields_of_the_body(self) -> None:
        e = await self.thrown_by(lambda: self.client.queries.item(id="missing"))
        self.assertIsInstance(e, ItemNotFound)
        self.assertIsInstance(e, GraphLinkDomainError)
        self.assertEqual(e.id, "missing")
        self.assertEqual(e.message, "Item missing not found")

    async def test_it_can_be_caught_by_type(self) -> None:
        caught = ""
        try:
            await self.client.queries.item(id="conflict")
        except ItemConflict as e:
            caught = e.reason
        self.assertEqual(caught, "duplicate")

    async def test_a_status_with_its_own_value_matches_the_body_code(self) -> None:
        e = await self.thrown_by(lambda: self.client.queries.item(id="conflict"))
        self.assertIsInstance(e, ItemConflict)
        self.assertEqual(e.message, "Conflict")

    async def test_a_custom_field_path_is_read_from_the_body(self) -> None:
        e = await self.thrown_by(lambda: self.client.queries.item(id="rate"))
        self.assertIsInstance(e, RateLimited)
        self.assertEqual(e.retry_after, 30)

    async def test_a_status_only_error_does_not_need_a_json_body(self) -> None:
        self.assertIsInstance(await self.thrown_by(lambda: self.client.queries.item(id="teapot")), Teapot)

    async def test_a_status_only_error_with_an_html_body_still_matches_by_status(self) -> None:
        e = await self.thrown_by(lambda: self.client.queries.item(id="html-404"))
        self.assertIsInstance(e, ItemNotFound)
        self.assertIsNone(e.id)

    async def test_a_mutation_throws_its_declared_error(self) -> None:
        e = await self.thrown_by(lambda: self.client.mutations.create_item(input=ItemInput(name="dup")))
        self.assertIsInstance(e, ItemConflict)
        self.assertEqual(e.reason, "name taken")

    async def test_a_mutation_returns_its_data(self) -> None:
        self.assertEqual((await self.client.mutations.create_item(input=ItemInput(name="fresh"))).id, "new")

    async def test_falls_back_to_rest_error(self) -> None:
        cases = [
            ("a body missing a required field", "conflict-no-reason", 409),
            ("a code the client does not know", "conflict-other", 409),
            ("a proxy error with an HTML body", "bad-gateway", 502),
        ]
        for name, id, status in cases:
            with self.subTest(name):
                e = await self.thrown_by(lambda: self.client.queries.item(id=id))
                self.assertIsInstance(e, RestError)
                self.assertNotIsInstance(e, GraphLinkDomainError)
                self.assertEqual(e.status, status)

    async def test_an_operation_without_throws_keeps_rest_error(self) -> None:
        e = await self.thrown_by(lambda: self.client.queries.item_plain(id="x"))
        self.assertIsInstance(e, RestError)
        self.assertEqual(e.status, 404)
