import asyncio
import time
import unittest
from typing import Any, Awaitable

import httpx

from generated import GraphLinkClient, GraphLinkHttpxAdapter, GraphLinkRestHttpxAdapter

from .variant import FAULT_PORT

FAULT_URL = f"http://127.0.0.1:{FAULT_PORT}"


class CancelledCall(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.http = httpx.AsyncClient()
        await self.http.post(f"{FAULT_URL}/_reset")
        self.rest = GraphLinkRestHttpxAdapter(base_url=FAULT_URL)
        self.graphql = GraphLinkHttpxAdapter(url=f"{FAULT_URL}/graphql")
        self.client = GraphLinkClient(adapter=self.graphql.call, rest_adapter=self.rest)

    async def asyncTearDown(self) -> None:
        await self.rest.aclose()
        await self.graphql.aclose()
        await self.http.aclose()

    def call(self, op: str) -> Awaitable[Any]:
        if op == "g":
            return self.client.queries.get_count()
        if op == "c":
            return self.client.queries.count()
        if op == "k":
            return self.client.queries.cached_status(code=200)
        return self.client.queries.status(code=200)

    async def test_a_cancelled_call_returns_promptly_and_leaves_the_client_usable(self) -> None:
        for op in "gcpk":
            for mode in ("cancel", "timeout"):
                with self.subTest(op=op, mode=mode):
                    self.client = GraphLinkClient(adapter=self.graphql.call, rest_adapter=self.rest)
                    await self.http.post(f"{FAULT_URL}/_arm", params={"fault": "slow"})
                    started = time.monotonic()
                    if mode == "timeout":
                        with self.assertRaises(asyncio.TimeoutError):
                            await asyncio.wait_for(self.call(op), timeout=0.2)
                    else:
                        task = asyncio.ensure_future(self.call(op))
                        await asyncio.sleep(0.2)
                        task.cancel()
                        with self.assertRaises(asyncio.CancelledError):
                            await task
                    self.assertLess(time.monotonic() - started, 0.7, "waited for a response nobody wanted")
                    await asyncio.wait_for(self.call(op), timeout=5)
