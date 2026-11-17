import asyncio
import subprocess
import time
import unittest
from typing import Callable, Dict, List, Optional

from .real_server import new_client, new_ws_adapter
from .test_subscription_reconnect import kill_port, start_server

PORT = 9931


class Stream:
    def __init__(self, client, label: str, count: int) -> None:
        self.events: List[str] = []
        self.error: Optional[BaseException] = None
        self.ended = False
        self.task = asyncio.ensure_future(self._consume(client, label, count))

    async def _consume(self, client, label: str, count: int) -> None:
        try:
            async for event in client.subscriptions.label_ticks(label=label, count=count):
                self.events.append(event.label_ticks)
            self.ended = True
        except asyncio.CancelledError:
            raise
        except Exception as e:
            self.error = e

    async def wait_events(self, label: str, timeout: float = 60) -> None:
        deadline = time.time() + timeout
        seen = len(self.events)
        while len([e for e in self.events[seen:] if e.startswith(label + "-")]) == 0:
            if time.time() > deadline:
                raise AssertionError(f"no event for {label} after the restart")
            await asyncio.sleep(0.2)

    def cancel(self) -> None:
        self.task.cancel()


class ReconnectCasesTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.processes: List[subprocess.Popen] = []
        self.streams: List[Stream] = []
        self.ws = None
        self.reconnects = 0
        await self.restart()

    async def asyncTearDown(self) -> None:
        for stream in self.streams:
            stream.cancel()
        if self.ws is not None:
            await self.ws.close()
        for process in self.processes:
            process.kill()
        kill_port(PORT)

    async def restart(self) -> None:
        self.processes.append(await asyncio.to_thread(start_server, PORT))

    def client(self, headers_provider: Optional[Callable] = None, **adapter_args):
        self.ws = new_ws_adapter(PORT, headers_provider=headers_provider, **adapter_args)
        client = new_client(PORT, ws_adapter=self.ws)
        original = self.ws.on_reconnect

        def on_reconnect() -> None:
            original()
            self.reconnects += 1

        self.ws.on_reconnect = on_reconnect
        return client

    def subscribe(self, client, label: str, count: int = 1000) -> Stream:
        stream = Stream(client, label, count)
        self.streams.append(stream)
        return stream

    async def first_event(self, stream: Stream) -> None:
        deadline = time.time() + 10
        while not stream.events:
            self.assertLess(time.time(), deadline, "no first event")
            await asyncio.sleep(0.1)

    async def starts(self, client, label: str) -> int:
        return (await client.queries.label_tick_starts(label=label)).label_tick_starts

    async def await_reconnect(self, count: int = 1) -> None:
        deadline = time.time() + 60
        while self.reconnects < count:
            self.assertLess(time.time(), deadline, "the adapter did not reconnect")
            await asyncio.sleep(0.2)

    async def test_resubscribes_with_the_same_variables(self) -> None:
        client = self.client()
        stream = self.subscribe(client, "bob")
        await self.first_event(stream)
        self.assertEqual(stream.events[0], "bob-1")

        await self.restart()
        await self.await_reconnect()
        await stream.wait_events("bob")
        self.assertEqual(await self.starts(client, "bob"), 1)

    async def test_does_not_resubscribe_a_completed_subscription(self) -> None:
        client = self.client()
        stream = self.subscribe(client, "done", 2)
        deadline = time.time() + 10
        while not stream.ended:
            self.assertLess(time.time(), deadline, "the stream did not complete")
            await asyncio.sleep(0.1)
        self.assertEqual(len(stream.events), 2)

        await self.restart()
        await asyncio.sleep(6)
        self.assertEqual(await self.starts(client, "done"), 0)
        self.assertEqual(len(stream.events), 2)

    async def test_does_not_revive_a_cancelled_subscription(self) -> None:
        client = self.client()
        stream = self.subscribe(client, "cancelled")
        await self.first_event(stream)
        stream.cancel()
        await asyncio.sleep(1)

        await self.restart()
        await asyncio.sleep(6)
        self.assertEqual(await self.starts(client, "cancelled"), 0)

    async def test_resumes_every_open_subscription_on_one_socket(self) -> None:
        client = self.client()
        a, b = self.subscribe(client, "a"), self.subscribe(client, "b")
        await self.first_event(a)
        await self.first_event(b)

        await self.restart()
        await self.await_reconnect()
        await a.wait_events("a")
        await b.wait_events("b")
        self.assertEqual(await self.starts(client, "a"), 1)
        self.assertEqual(await self.starts(client, "b"), 1)

    async def test_a_restart_during_connection_init_subscribes_once(self) -> None:
        async def provider() -> Dict[str, str]:
            return {"Ack-Delay": "3000"}

        client = self.client(provider)
        stream = self.subscribe(client, "init")
        await asyncio.sleep(1)

        await self.restart()
        await stream.wait_events("init")
        await asyncio.sleep(2)
        self.assertEqual(await self.starts(client, "init"), 1)

    async def test_a_server_down_longer_than_the_ack_timeout_still_resumes(self) -> None:
        async def provider() -> Dict[str, str]:
            return {"Ack-Delay": "3000"}

        client = self.client(provider)
        stream = self.subscribe(client, "init")
        await asyncio.sleep(1)

        kill_port(PORT)
        await asyncio.sleep(8)
        await self.restart()
        await stream.wait_events("init")
        self.assertIsNone(stream.error)
        self.assertEqual(await self.starts(client, "init"), 1)

    async def test_gives_up_with_a_visible_error(self) -> None:
        client = self.client(max_reconnect_attempts=2, max_reconnect_delay=1.0)
        stream = self.subscribe(client, "giveup")
        await self.first_event(stream)
        kill_port(PORT)

        deadline = time.time() + 60
        while stream.error is None and not stream.ended:
            self.assertLess(time.time(), deadline, "the stream neither failed nor ended after the reconnect attempts ran out")
            await asyncio.sleep(0.5)
        self.assertIsNotNone(stream.error)
