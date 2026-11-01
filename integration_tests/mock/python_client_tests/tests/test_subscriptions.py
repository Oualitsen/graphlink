import asyncio
import unittest
from typing import Any, AsyncIterator, List

from generated import GraphLinkClient, UserStatus

from . import fixtures as fx
from .mock_adapter import MockAdapter, MockWebSocketAdapter

TIMEOUT = 5


async def drain(stream: AsyncIterator[Any], sink: List[Any]) -> None:
    async for event in stream:
        sink.append(event)


class SubscriptionsTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self) -> None:
        self.adapter = MockAdapter()
        self.ws = MockWebSocketAdapter()
        self.client = GraphLinkClient(adapter=self.adapter.call, ws_adapter=self.ws)

    async def ready(self) -> None:
        await asyncio.wait_for(self.ws.subscription_ready(), TIMEOUT)

    async def settle(self) -> None:
        for _ in range(5):
            await asyncio.sleep(0)

    async def test_single_event_is_deserialized(self) -> None:
        stream = self.client.subscriptions.user_created()
        first = asyncio.ensure_future(stream.__anext__())
        await self.ready()
        self.ws.push_event({"userCreated": fx.USER_ALICE})
        event = await asyncio.wait_for(first, TIMEOUT)
        self.assertEqual(event.user_created.id, "user-1")
        self.assertEqual(event.user_created.name, "Alice Smith")
        self.assertIs(event.user_created.status, UserStatus.ACTIVE)
        await stream.aclose()

    async def test_multiple_events_in_order(self) -> None:
        events: List[Any] = []
        stream = self.client.subscriptions.user_created()
        task = asyncio.ensure_future(drain(stream, events))
        await self.ready()
        self.ws.push_event({"userCreated": fx.USER_ALICE})
        self.ws.push_event({"userCreated": fx.USER_BOB})
        await self.settle()
        self.assertEqual([e.user_created.id for e in events], ["user-1", "user-2"])
        self.ws.push_complete()
        await asyncio.wait_for(task, TIMEOUT)

    async def test_complete_closes_the_stream(self) -> None:
        events: List[Any] = []
        task = asyncio.ensure_future(drain(self.client.subscriptions.user_created(), events))
        await self.ready()
        self.ws.push_event({"userCreated": fx.USER_ALICE})
        self.ws.push_complete()
        await asyncio.wait_for(task, TIMEOUT)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0].user_created.id, "user-1")

    async def test_cancelling_stops_event_delivery(self) -> None:
        events: List[Any] = []
        task = asyncio.ensure_future(drain(self.client.subscriptions.user_created(), events))
        await self.ready()
        self.ws.push_event({"userCreated": fx.USER_ALICE})
        await self.settle()
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task
        self.ws.push_event({"userCreated": fx.USER_BOB})
        await self.settle()
        self.assertEqual(len(events), 1)

    async def test_status_changed_event(self) -> None:
        stream = self.client.subscriptions.user_status_changed(user_id="user-1")
        first = asyncio.ensure_future(stream.__anext__())
        await self.ready()
        self.ws.push_event({"userStatusChanged": fx.USER_ALICE})
        event = await asyncio.wait_for(first, TIMEOUT)
        self.assertEqual(event.user_status_changed.id, "user-1")
        self.assertIs(event.user_status_changed.status, UserStatus.ACTIVE)
        await stream.aclose()

    async def test_variables_are_sent_in_subscribe_message(self) -> None:
        stream = self.client.subscriptions.user_status_changed(user_id="user-42")
        first = asyncio.ensure_future(stream.__anext__())
        await self.ready()
        subscribe = next(m for m in self.ws.sent_messages if m["type"] == "subscribe")
        self.assertEqual(subscribe["payload"]["variables"]["userId"], "user-42")
        first.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await first
        await stream.aclose()


if __name__ == "__main__":
    unittest.main()
