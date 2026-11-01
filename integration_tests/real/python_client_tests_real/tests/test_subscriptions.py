import asyncio
import unittest
from typing import Any, AsyncIterator, List

from generated import UserStatus

from .real_server import new_ws_adapter, new_client

TIMEOUT = 10


async def first(stream: AsyncIterator[Any]) -> Any:
    try:
        return await asyncio.wait_for(stream.__anext__(), TIMEOUT)
    finally:
        await stream.aclose()


async def take(stream: AsyncIterator[Any], count: int) -> List[Any]:
    events: List[Any] = []
    try:
        while len(events) < count:
            events.append(await asyncio.wait_for(stream.__anext__(), TIMEOUT))
    finally:
        await stream.aclose()
    return events


class RealSubscriptionsTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.ws = new_ws_adapter()
        self.client = new_client(ws_adapter=self.ws)

    async def asyncTearDown(self) -> None:
        await self.ws.close()

    async def test_user_created_first_event(self) -> None:
        event = await first(self.client.subscriptions.user_created())
        self.assertEqual((event.user_created.id, event.user_created.name), ("user-1", "Alice Smith"))
        self.assertIs(event.user_created.status, UserStatus.ACTIVE)

    async def test_user_created_multiple_events(self) -> None:
        events = await take(self.client.subscriptions.user_created(), 2)
        self.assertEqual([e.user_created.id for e in events], ["user-1", "user-2"])

    async def test_user_status_changed(self) -> None:
        one = await first(self.client.subscriptions.user_status_changed(user_id="user-1"))
        self.assertEqual((one.user_status_changed.id, one.user_status_changed.status), ("user-1", UserStatus.ACTIVE))
        two = await first(self.client.subscriptions.user_status_changed(user_id="user-2"))
        self.assertEqual((two.user_status_changed.id, two.user_status_changed.status), ("user-2", UserStatus.INACTIVE))

    async def test_user_createds_list_event(self) -> None:
        event = await first(self.client.subscriptions.user_createds(ids=["user-1", "user-2"]))
        self.assertEqual([u.id for u in event.user_createds], ["user-1", "user-2"])

    async def test_concurrent_subscriptions_on_one_connection(self) -> None:
        user, counter = await asyncio.gather(
            first(self.client.subscriptions.user_created()),
            first(self.client.subscriptions.counter_tick()),
        )
        self.assertEqual(user.user_created.id, "user-1")
        self.assertIsInstance(counter.counter_tick, int)

    async def test_independent_subscriptions_with_different_arguments(self) -> None:
        one, two = await asyncio.gather(
            first(self.client.subscriptions.user_status_changed(user_id="user-1")),
            first(self.client.subscriptions.user_status_changed(user_id="user-2")),
        )
        self.assertEqual(one.user_status_changed.id, "user-1")
        self.assertEqual(two.user_status_changed.id, "user-2")

    async def test_two_streams_of_the_same_subscription(self) -> None:
        a, b = await asyncio.gather(
            take(self.client.subscriptions.user_created(), 2),
            take(self.client.subscriptions.user_created(), 2),
        )
        self.assertEqual([e.user_created.id for e in a], ["user-1", "user-2"])
        self.assertEqual([e.user_created.id for e in b], ["user-1", "user-2"])

    async def test_cancelling_one_subscription_does_not_stop_the_other(self) -> None:
        ticks = self.client.subscriptions.counter_tick()
        count = 0

        async def consume() -> None:
            nonlocal count
            async for _ in ticks:
                count += 1

        task = asyncio.ensure_future(consume())
        other = await first(self.client.subscriptions.user_created())
        self.assertEqual(other.user_created.id, "user-1")
        await asyncio.sleep(2)
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task
        self.assertGreaterEqual(count, 1)


if __name__ == "__main__":
    unittest.main()
