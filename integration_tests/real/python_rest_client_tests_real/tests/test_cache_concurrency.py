import asyncio
import time

from generated import InMemoryGraphLinkCacheStore

from .support import RestTestCase

_sequence = 0


class CacheConcurrency(RestTestCase):
    async def asyncSetUp(self) -> None:
        global _sequence
        await super().asyncSetUp()
        _sequence += 1
        self.name = f"py-{time.time_ns()}-{_sequence}"

    async def test_concurrent_requests_for_two_different_keys_make_two_calls(self) -> None:
        await asyncio.gather(
            self.client.queries.counter_slow(name=f"{self.name}-a", delay_ms=300),
            self.client.queries.counter_slow(name=f"{self.name}-b", delay_ms=300),
        )
        self.assertEqual((await self.client.queries.counter_calls(name=f"{self.name}-a")).n, 1)
        self.assertEqual((await self.client.queries.counter_calls(name=f"{self.name}-b")).n, 1)

    async def test_concurrent_requests_for_the_same_key_share_one_call(self) -> None:
        results = await asyncio.gather(
            *[self.client.queries.counter_slow(name=self.name, delay_ms=300) for _ in range(3)]
        )
        self.assertEqual([r.n for r in results], [1, 1, 1])
        self.assertEqual((await self.client.queries.counter_calls(name=self.name)).n, 1)

    async def test_a_response_in_flight_during_an_invalidation_is_not_stored(self) -> None:
        slow = asyncio.ensure_future(self.client.queries.counter_slow(name=self.name, delay_ms=600))
        await asyncio.sleep(0.15)
        await self.client.mutations.touch_slow(name=self.name)
        self.assertEqual((await slow).n, 1)
        self.assertEqual((await self.client.queries.counter_slow(name=self.name, delay_ms=600)).n, 2)

    async def test_an_invalidation_that_arrives_while_the_response_is_being_stored_removes_it(self) -> None:
        reached = asyncio.Event()
        release = asyncio.Event()

        class PausingStore(InMemoryGraphLinkCacheStore):
            paused = False

            async def set(self, key: str, value: str) -> None:
                if not key.startswith("__tag__") and not self.paused:
                    self.paused = True
                    reached.set()
                    await release.wait()
                await super().set(key, value)

        pausing = self.new_client(store=PausingStore())
        first = asyncio.ensure_future(pausing.queries.counter_slow(name=self.name, delay_ms=50))
        await reached.wait()
        touch = asyncio.ensure_future(pausing.mutations.touch_slow(name=self.name))
        await asyncio.sleep(0.3)
        release.set()
        await asyncio.gather(first, touch)
        self.assertEqual((await pausing.queries.counter_slow(name=self.name, delay_ms=50)).n, 2)
