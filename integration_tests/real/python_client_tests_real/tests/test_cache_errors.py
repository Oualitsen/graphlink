import itertools
import time
import unittest

from generated import GraphLinkException

from .real_server import new_client

_next = itertools.count()


class FailedResponsesAreNotCachedTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()
        self.id = f"py-{time.time_ns()}-{next(_next)}"

    async def server_calls(self) -> int:
        return (await self.client.queries.cached_flaky_calls(id=self.id)).cached_flaky_calls

    async def test_the_success_after_a_failure_is_fetched_then_served_from_the_cache(self) -> None:
        with self.assertRaises(GraphLinkException):
            await self.client.queries.cached_flaky(id=self.id)
        self.assertEqual(await self.server_calls(), 1)

        self.assertEqual((await self.client.queries.cached_flaky(id=self.id)).cached_flaky.id, "user-1")
        self.assertEqual(await self.server_calls(), 2)

        self.assertEqual((await self.client.queries.cached_flaky(id=self.id)).cached_flaky.id, "user-1")
        self.assertEqual(await self.server_calls(), 2)

    async def test_a_partial_failure_is_not_cached_either(self) -> None:
        with self.assertRaises(GraphLinkException):
            await self.client.queries.cached_flaky_nullable(id=self.id)
        self.assertEqual(await self.server_calls(), 1)

        self.assertEqual((await self.client.queries.cached_flaky_nullable(id=self.id)).cached_flaky_nullable.id, "user-1")
        self.assertEqual(await self.server_calls(), 2)

        self.assertEqual((await self.client.queries.cached_flaky_nullable(id=self.id)).cached_flaky_nullable.id, "user-1")
        self.assertEqual(await self.server_calls(), 2)
