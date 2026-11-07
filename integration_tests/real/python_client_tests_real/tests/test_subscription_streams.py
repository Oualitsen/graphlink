import asyncio
import unittest
from typing import Any, AsyncIterator, List, Tuple

from generated import ListsInput, OnlyOne, Spelling

from .real_server import new_client, new_ws_adapter

TIMEOUT = 10


async def drain(stream: AsyncIterator[Any]) -> Tuple[List[Any], BaseException | None]:
    events: List[Any] = []
    try:
        while True:
            events.append(await asyncio.wait_for(stream.__anext__(), TIMEOUT))
    except StopAsyncIteration:
        return events, None
    except Exception as e:
        return events, e


class RealSubscriptionStreamsTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.ws = new_ws_adapter()
        self.client = new_client(ws_adapter=self.ws)

    async def asyncTearDown(self) -> None:
        await self.ws.close()

    async def test_every_argument_shape_round_trips(self) -> None:
        events, error = await drain(self.client.subscriptions.sub_echo_args(
            a=[1, 2], b=[1, None], c=[[1], [], [2, 3]],
            e=[Spelling.X_Y, Spelling.HTTP2_OK], f=[None, Spelling.V1],
        ))
        self.assertIsNone(error)
        self.assertEqual(len(events), 1)
        r = events[0].sub_echo_args
        self.assertEqual(r.a, [1, 2])
        self.assertEqual(r.b, [1, None])
        self.assertEqual(r.c, [[1], [], [2, 3]])
        self.assertEqual(r.e, [Spelling.X_Y, Spelling.HTTP2_OK])
        self.assertEqual(r.f, [None, Spelling.V1])

    async def test_omitted_arguments_are_null_and_defaults_apply(self) -> None:
        events, _ = await drain(self.client.subscriptions.sub_echo_args(a=[], e=[]))
        r = events[0].sub_echo_args
        self.assertIsNone(r.b)
        self.assertIsNone(r.c)
        self.assertIsNone(r.f)
        self.assertEqual(r.g, [Spelling.A, Spelling.B2])
        self.assertEqual(r.one, OnlyOne.ONLY)

    async def test_input_object_round_trips(self) -> None:
        events, _ = await drain(self.client.subscriptions.sub_echo_input(input=ListsInput(
            a=[3, 4], b=[None, 5], c=[[1, 2], []], e=[Spelling.SNAKE_CASE_2], f=[Spelling.A, None], g=[Spelling.V1],
        )))
        r = events[0].sub_echo_input
        self.assertEqual(r.a, [3, 4])
        self.assertEqual(r.b, [None, 5])
        self.assertEqual(r.c, [[1, 2], []])
        self.assertEqual(r.e, [Spelling.SNAKE_CASE_2])
        self.assertEqual(r.f, [Spelling.A, None])
        self.assertEqual(r.g, [Spelling.V1])

    async def test_server_completion_ends_the_iterator(self) -> None:
        events, error = await drain(self.client.subscriptions.finite_ticks(count=5))
        self.assertIsNone(error)
        self.assertEqual([e.finite_ticks for e in events], [1, 2, 3, 4, 5])

    async def test_completion_without_events_is_an_empty_iterator(self) -> None:
        events, error = await drain(self.client.subscriptions.finite_ticks(count=0))
        self.assertEqual(events, [])
        self.assertIsNone(error)

    async def test_events_before_the_failure_arrive_then_the_error(self) -> None:
        events, error = await drain(self.client.subscriptions.flaky_ticks(fail_after=3))
        self.assertEqual([e.flaky_ticks for e in events], [1, 2, 3])
        self.assertIsNotNone(error)

    async def test_failure_before_the_first_event(self) -> None:
        events, error = await drain(self.client.subscriptions.flaky_ticks(fail_after=0))
        self.assertEqual(events, [])
        self.assertIsNotNone(error)

    async def test_failed_stream_does_not_break_the_next_subscription(self) -> None:
        await drain(self.client.subscriptions.flaky_ticks(fail_after=1))
        events, error = await drain(self.client.subscriptions.finite_ticks(count=2))
        self.assertIsNone(error)
        self.assertEqual(len(events), 2)
