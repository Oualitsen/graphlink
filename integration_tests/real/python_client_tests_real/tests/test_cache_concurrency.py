import asyncio
import itertools
import time
import unittest

from .real_server import new_client

_next = itertools.count()


class CachedRequestsAtTheSameTimeTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.client = new_client()
        self.id = f"py-{time.time_ns()}-{next(_next)}"

    async def test_concurrent_requests_for_two_different_keys_make_two_calls(self) -> None:
        await asyncio.gather(
            self.client.queries.cached_slow(id=f"{self.id}-a", delay_ms=300),
            self.client.queries.cached_slow(id=f"{self.id}-b", delay_ms=300),
        )
        for key in ("a", "b"):
            calls = await self.client.queries.cached_slow_calls(id=f"{self.id}-{key}")
            self.assertEqual(calls.cached_slow_calls, 1)

    async def test_concurrent_requests_for_the_same_key_share_one_call(self) -> None:
        results = await asyncio.gather(
            *[self.client.queries.cached_slow(id=self.id, delay_ms=300) for _ in range(3)]
        )
        self.assertEqual([r.cached_slow for r in results], [0, 0, 0])
        self.assertEqual((await self.client.queries.cached_slow_calls(id=self.id)).cached_slow_calls, 1)

    async def test_a_response_in_flight_during_an_invalidation_is_not_stored(self) -> None:
        slow = asyncio.create_task(self.client.queries.cached_slow(id=self.id, delay_ms=600))
        await asyncio.sleep(0.15)
        await self.client.mutations.bump_slow(id=self.id)
        self.assertEqual((await slow).cached_slow, 0)
        self.assertEqual((await self.client.queries.cached_slow(id=self.id, delay_ms=600)).cached_slow, 1)
